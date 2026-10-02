-- ============================================================================
-- AMAZON PRODUCTS SALES ANALYSIS 2023 — FINAL PRODUCTION PIPELINE
-- ============================================================================
-- Dataset   : product_analiysis (BigQuery)   [nama dataset dipertahankan
--             sesuai project existing; ganti jika ingin memperbaiki typo]
-- Tujuan    : Mengubah raw table hasil scraping menjadi fact table bersih
--             + mart table siap pakai untuk dashboard (Looker Studio).
--
-- STRUKTUR FILE (7 Fase, dieksekusi berurutan dari atas ke bawah):
--   FASE 1  Data Profiling            -> query diagnostik, tidak membuat tabel
--   FASE 2  Staging Layer             -> stg_amazon_products
--   FASE 3  Data Quality & Dedup Layer-> stg_amazon_products_quality
--   FASE 4  Fact Layer (Clean+Feature)-> fact_products_clean
--   FASE 5  Validasi Fact Table       -> query diagnostik
--   FASE 6  Mart Layer (Dashboard)    -> mart_category_summary, dst.
--   FASE 7  Data Quality Report Mart  -> mart_data_quality
--
-- CATATAN PENTING:
-- Uji statistik inferensial (korelasi Spearman per kategori, Kruskal-Wallis,
-- Mann-Whitney + FDR correction) SENGAJA TIDAK dikerjakan di SQL.
-- Semua pindah ke notebook Python (Amazon_Products_Final_Analysis.ipynb)
-- karena scipy/statsmodels jauh lebih reliable, teruji, dan ringkas
-- dibanding reimplementasi manual (JS UDF) yang sebelumnya memakan
-- ribuan baris dan sulit diverifikasi.
-- ============================================================================


-- ============================================================================
-- FASE 1 — DATA PROFILING (sebelum cleaning apapun)
-- Tujuan: mengukur skala masalah dengan angka pasti, bukan asumsi.
-- Semua query di fase ini bersifat diagnostik (SELECT biasa), tidak membuat
-- tabel baru. Jalankan satu per satu untuk inspeksi manual.
-- ============================================================================

-- 1.1 Skema & tipe data kolom saat ini
SELECT column_name, data_type, is_nullable
FROM `product_analiysis.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'amazon_product'
ORDER BY ordinal_position;

-- 1.2 Volume total & missing value per kolom
SELECT
  COUNT(*)                                   AS total_rows,
  COUNTIF(name IS NULL)                      AS missing_name,
  COUNTIF(main_category IS NULL)             AS missing_main_category,
  COUNTIF(sub_category IS NULL)              AS missing_sub_category,
  COUNTIF(link IS NULL)                      AS missing_link,
  COUNTIF(ratings IS NULL)                   AS missing_ratings,
  COUNTIF(no_of_ratings IS NULL)             AS missing_no_of_ratings,
  COUNTIF(discount_price IS NULL)            AS missing_discount_price,
  COUNTIF(actual_price IS NULL)              AS missing_actual_price
FROM `product_analiysis.amazon_product`;

-- 1.3 Duplikat exact row (semua kolom identik)
SELECT
  COUNT(*)                                        AS total_rows,
  COUNT(DISTINCT TO_JSON_STRING(t))                AS unique_rows,
  COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(t))      AS exact_duplicate_rows
FROM `product_analiysis.amazon_product` AS t;

-- 1.4 Format tidak valid pada kolom numerik-yang-masih-string
SELECT
  COUNTIF(ratings IS NOT NULL AND SAFE_CAST(TRIM(ratings) AS FLOAT64) IS NULL)
    AS invalid_rating_format,
  COUNTIF(no_of_ratings IS NOT NULL
    AND SAFE_CAST(REPLACE(TRIM(no_of_ratings), ',', '') AS INT64) IS NULL)
    AS invalid_no_of_ratings_format
FROM `product_analiysis.amazon_product`;

-- 1.5 Anomali harga
SELECT
  COUNTIF(actual_price = 0)              AS zero_actual_price,
  COUNTIF(actual_price < 0)              AS negative_actual_price,
  COUNTIF(discount_price < 0)            AS negative_discount_price,
  COUNTIF(discount_price > actual_price) AS discount_above_actual
FROM `product_analiysis.amazon_product`
WHERE actual_price IS NOT NULL AND discount_price IS NOT NULL;

-- 1.6 Kardinalitas kategori (cek inkonsistensi penulisan)
SELECT main_category, sub_category, COUNT(*) AS product_count
FROM `product_analiysis.amazon_product`
GROUP BY main_category, sub_category
ORDER BY main_category, product_count DESC;

-- 1.7 Cakupan ASIN pada kolom link (basis primary key nanti)
SELECT
  COUNT(*) AS total_rows,
  COUNTIF(REGEXP_CONTAINS(link, r'/dp/[A-Z0-9]{10}')) AS links_with_asin,
  ROUND(COUNTIF(REGEXP_CONTAINS(link, r'/dp/[A-Z0-9]{10}')) * 100.0 / COUNT(*), 2)
    AS asin_coverage_pct
FROM `product_analiysis.amazon_product`;


-- ============================================================================
-- FASE 2 — STAGING LAYER
-- Tujuan: casting tipe data & standardisasi teks. Tabel ini MASIH mengandung
-- duplikat dan anomali — belum "bersih", baru benar tipenya.
-- ============================================================================

CREATE OR REPLACE TABLE `product_analiysis.stg_amazon_products` AS
SELECT
  int64_field_0                                    AS source_id,
  TRIM(name)                                        AS name,
  LOWER(TRIM(main_category))                        AS main_category,
  LOWER(TRIM(sub_category))                         AS sub_category,
  TRIM(link)                                        AS link,

  -- ASIN = identitas produk paling reliable (bukan 'name' yang rawan typo)
  REGEXP_EXTRACT(link, r'/dp/([A-Z0-9]{10})')        AS asin,

  -- Rating: hanya nilai numerik valid yang lolos; sisanya jadi NULL (bukan error)
  SAFE_CAST(TRIM(ratings) AS FLOAT64)                AS rating,

  -- Review count: hapus koma ribuan dulu sebelum cast
  SAFE_CAST(REPLACE(TRIM(no_of_ratings), ',', '') AS INT64) AS review_count,

  SAFE_CAST(discount_price AS FLOAT64)               AS discount_price,
  SAFE_CAST(actual_price AS FLOAT64)                 AS actual_price

FROM `product_analiysis.amazon_product`;


-- ============================================================================
-- FASE 3 — DATA QUALITY & DEDUPLICATION LAYER
-- Tujuan: MENANDAI (bukan langsung membuang) setiap baris dengan flag kualitas,
-- lalu secara eksplisit MENENTUKAN baris kanonik untuk setiap produk unik.
--
-- Definisi "produk unik" = ASIN (hasil ekstraksi dari link).
-- Jika ASIN tidak tersedia (link rusak/kosong), fallback ke kombinasi
-- (name, main_category, sub_category).
--
-- Baris kanonik yang dipilih = source_id PALING KECIL per grup
-- (mewakili kemunculan pertama di data scraping asli).
-- ============================================================================

CREATE OR REPLACE TABLE `product_analiysis.stg_amazon_products_quality` AS

WITH keyed AS (
  SELECT
    *,
    COALESCE(asin, CONCAT(name, '|', main_category, '|', sub_category))
      AS dedup_key
  FROM `product_analiysis.stg_amazon_products`
),

ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY dedup_key
      ORDER BY source_id ASC
    ) AS dedup_rank
  FROM keyed
),

-- Batas IQR untuk deteksi outlier harga, dihitung PER sub_category
-- (bukan global) karena skala harga sangat berbeda antar kategori produk.
price_bounds AS (
  SELECT
    sub_category,
    APPROX_QUANTILES(actual_price, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(actual_price, 100)[OFFSET(75)] AS q3
  FROM ranked
  WHERE actual_price IS NOT NULL AND actual_price > 0
  GROUP BY sub_category
),

price_bounds_iqr AS (
  SELECT
    sub_category,
    q1 - 1.5 * (q3 - q1) AS lower_bound,
    q3 + 1.5 * (q3 - q1) AS upper_bound
  FROM price_bounds
)

SELECT
  r.source_id,
  r.name,
  r.main_category,
  r.sub_category,
  r.link,
  r.asin,
  r.rating,
  r.review_count,
  r.discount_price,
  r.actual_price,
  r.dedup_key,

  -- Flag: apakah baris ini duplikat dari produk yang sama (bukan kanonik)
  CASE WHEN r.dedup_rank > 1 THEN 1 ELSE 0 END          AS is_duplicate,

  -- Flag kualitas data per baris
  CASE WHEN r.rating IS NULL THEN 1 ELSE 0 END           AS flag_missing_rating,
  CASE WHEN r.review_count IS NULL THEN 1 ELSE 0 END     AS flag_missing_review_count,
  CASE WHEN r.actual_price IS NULL OR r.actual_price = 0
       THEN 1 ELSE 0 END                                 AS flag_price_anomaly,
  CASE WHEN r.discount_price IS NOT NULL
        AND r.actual_price IS NOT NULL
        AND r.discount_price > r.actual_price
       THEN 1 ELSE 0 END                                 AS flag_discount_above_actual,

  -- Flag outlier harga berbasis IQR per sub_category
  CASE
    WHEN r.actual_price IS NOT NULL
     AND b.lower_bound IS NOT NULL
     AND (r.actual_price < b.lower_bound OR r.actual_price > b.upper_bound)
    THEN 1 ELSE 0
  END AS flag_price_outlier

FROM ranked r
LEFT JOIN price_bounds_iqr b
  ON r.sub_category = b.sub_category;


-- 3.1 Ringkasan hasil dedup & flagging (cek sebelum lanjut ke fact table)
SELECT
  COUNT(*)                         AS total_rows,
  COUNTIF(is_duplicate = 1)        AS duplicate_rows_removed,
  COUNTIF(flag_price_anomaly = 1)  AS price_anomaly_rows,
  COUNTIF(flag_price_outlier = 1)  AS price_outlier_rows,
  COUNTIF(flag_missing_rating = 1) AS missing_rating_rows
FROM `product_analiysis.stg_amazon_products_quality`;


-- ============================================================================
-- FASE 4 — FACT LAYER: CLEANING FINAL + FEATURE ENGINEERING
-- Tujuan: tabel akhir siap pakai untuk EDA & statistik.
-- Hanya berisi baris KANONIK (is_duplicate = 0).
-- Baris anomali/outlier TETAP DISERTAKAN (tidak dibuang), tapi diberi flag,
-- supaya analis bisa memilih sendiri apakah mau exclude saat query.
-- ============================================================================

CREATE OR REPLACE TABLE `product_analiysis.fact_products_clean` AS

WITH base AS (
  SELECT *
  FROM `product_analiysis.stg_amazon_products_quality`
  WHERE is_duplicate = 0
),

-- price_bucket: tertile harga PER sub_category (budget/mid/premium)
-- NTILE dihitung hanya pada baris dengan actual_price valid & positif,
-- lalu di-join balik agar baris tanpa harga tetap punya price_bucket = NULL
priced AS (
  SELECT
    asin,
    source_id,
    NTILE(3) OVER (
      PARTITION BY sub_category
      ORDER BY actual_price
    ) AS price_tertile
  FROM base
  WHERE actual_price IS NOT NULL AND actual_price > 0
)

SELECT
  b.source_id,
  b.name,
  b.main_category,
  b.sub_category,
  b.link,
  b.asin,
  b.rating,
  b.review_count,
  b.discount_price,
  b.actual_price,

  -- Selisih & persentase diskon (guard divide-by-zero)
  CASE WHEN b.discount_price IS NOT NULL AND b.actual_price IS NOT NULL
       THEN b.actual_price - b.discount_price END          AS discount_amount,

  CASE WHEN b.discount_price IS NOT NULL AND b.actual_price IS NOT NULL
        AND b.actual_price > 0
       THEN ROUND(((b.actual_price - b.discount_price) / b.actual_price) * 100, 2)
  END AS discount_pct,

  -- Flags biner untuk analisis & join cepat
  CASE WHEN b.discount_price IS NOT NULL AND b.actual_price IS NOT NULL
        AND b.discount_price < b.actual_price THEN 1 ELSE 0 END AS has_discount,
  CASE WHEN b.rating IS NOT NULL THEN 1 ELSE 0 END               AS has_rating,
  CASE WHEN b.review_count IS NOT NULL THEN 1 ELSE 0 END         AS has_review_count,

  -- rating_tier: cutoff bisnis tetap (sesuai kesepakatan awal proyek)
  CASE
    WHEN b.rating IS NULL THEN NULL
    WHEN b.rating < 3.5 THEN 'Low (<3.5)'
    WHEN b.rating < 4.2 THEN 'Medium (3.5-4.2)'
    ELSE 'High (>4.2)'
  END AS rating_tier,

  -- price_bucket: tertile per sub_category
  CASE p.price_tertile
    WHEN 1 THEN 'Budget'
    WHEN 2 THEN 'Mid'
    WHEN 3 THEN 'Premium'
  END AS price_bucket,

  -- Flag kualitas data dibawa dari staging layer (untuk transparansi &
  -- supaya analis bisa exclude sendiri saat butuh data "bersih murni")
  b.flag_price_anomaly,
  b.flag_price_outlier,
  b.flag_discount_above_actual

FROM base b
LEFT JOIN priced p
  ON b.asin = p.asin AND b.source_id = p.source_id;


-- ============================================================================
-- FASE 5 — VALIDASI FACT TABLE
-- Jalankan setelah FASE 4 untuk memastikan tabel akhir masuk akal.
-- ============================================================================

SELECT
  COUNT(*)                                   AS total_rows,
  COUNT(DISTINCT asin)                       AS unique_asin,
  COUNTIF(has_rating = 1)                    AS rows_with_rating,
  COUNTIF(has_discount = 1)                  AS rows_with_discount,
  COUNTIF(discount_pct < 0)                  AS negative_discount_pct,   -- harus 0
  COUNTIF(discount_pct > 100)                AS over_100_discount_pct,   -- harus 0
  COUNTIF(price_bucket IS NOT NULL)          AS rows_with_price_bucket,
  COUNTIF(rating_tier IS NOT NULL)           AS rows_with_rating_tier
FROM `product_analiysis.fact_products_clean`;


-- ============================================================================
-- FASE 6 — MART LAYER (sumber data untuk dashboard Looker Studio)
-- Prinsip: Looker Studio connect ke sini, BUKAN ke fact_products_clean
-- langsung, demi performa & agar logika agregasi terpusat di satu tempat.
-- ============================================================================

-- 6.1 Ringkasan per kategori (Halaman 1 — Executive Overview)
CREATE OR REPLACE TABLE `product_analiysis.mart_category_summary` AS
SELECT
  main_category,
  COUNT(*)                                        AS total_products,
  COUNT(DISTINCT sub_category)                    AS subcategory_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS product_share_pct,
  ROUND(AVG(rating), 2)                            AS avg_rating,
  ROUND(AVG(discount_pct), 2)                      AS avg_discount_pct,
  ROUND(APPROX_QUANTILES(actual_price, 100)[OFFSET(50)], 2) AS median_price,
  SUM(review_count)                                AS total_review_volume
FROM `product_analiysis.fact_products_clean`
WHERE flag_price_anomaly = 0
GROUP BY main_category
ORDER BY total_products DESC;

-- 6.2 Distribusi harga per kategori (Halaman 2 — Pricing & Discount)
CREATE OR REPLACE TABLE `product_analiysis.mart_price_distribution` AS
SELECT
  main_category,
  sub_category,
  COUNT(*)                                                     AS product_count,
  ROUND(APPROX_QUANTILES(actual_price, 100)[OFFSET(25)], 2)    AS p25_price,
  ROUND(APPROX_QUANTILES(actual_price, 100)[OFFSET(50)], 2)    AS median_price,
  ROUND(APPROX_QUANTILES(actual_price, 100)[OFFSET(75)], 2)    AS p75_price,
  ROUND(APPROX_QUANTILES(actual_price, 100)[OFFSET(95)], 2)    AS p95_price,
  ROUND(AVG(discount_pct), 2)                                  AS avg_discount_pct
FROM `product_analiysis.fact_products_clean`
WHERE flag_price_anomaly = 0 AND actual_price IS NOT NULL
GROUP BY main_category, sub_category;

-- 6.3 Performa band diskon vs review count (Halaman 2)
CREATE OR REPLACE TABLE `product_analiysis.mart_discount_band_performance` AS
SELECT
  CASE
    WHEN discount_pct < 20 THEN '0-20%'
    WHEN discount_pct < 40 THEN '20-40%'
    WHEN discount_pct < 60 THEN '40-60%'
    WHEN discount_pct < 80 THEN '60-80%'
    ELSE '80-100%'
  END AS discount_band,
  COUNT(*)                                  AS product_count,
  ROUND(AVG(review_count), 0)               AS avg_review_count,
  ROUND(APPROX_QUANTILES(review_count, 100)[OFFSET(50)], 0) AS median_review_count
FROM `product_analiysis.fact_products_clean`
WHERE discount_pct IS NOT NULL
  AND review_count IS NOT NULL
  AND flag_price_anomaly = 0
GROUP BY discount_band;

-- 6.4 Segmentasi produk per kategori (Halaman 3 — Popularity & Trust Matrix)
-- Baseline median dihitung PER main_category (hindari bias lintas kategori)
CREATE OR REPLACE TABLE `product_analiysis.mart_segment_distribution` AS
WITH baseline AS (
  SELECT
    main_category,
    APPROX_QUANTILES(rating, 100)[OFFSET(50)]        AS median_rating,
    APPROX_QUANTILES(review_count, 100)[OFFSET(50)]  AS median_review_count
  FROM `product_analiysis.fact_products_clean`
  WHERE flag_price_anomaly = 0 AND rating IS NOT NULL AND review_count IS NOT NULL
  GROUP BY main_category
),
segmented AS (
  SELECT
    f.main_category,
    f.sub_category,
    f.rating,
    f.review_count,
    f.actual_price,
    f.discount_pct,
    CASE
      WHEN f.rating >= b.median_rating AND f.review_count >= b.median_review_count
        THEN 'Best Seller'       -- rating tinggi, engagement tinggi
      WHEN f.rating >= b.median_rating AND f.review_count < b.median_review_count
        THEN 'Hidden Gem'        -- rating tinggi, belum populer
      WHEN f.rating < b.median_rating AND f.review_count >= b.median_review_count
        THEN 'Overhyped'         -- populer tapi rating di bawah rata-rata
      ELSE 'Risky'                -- rating rendah, engagement rendah
    END AS product_segment
  FROM `product_analiysis.fact_products_clean` f
  INNER JOIN baseline b ON f.main_category = b.main_category
  WHERE f.flag_price_anomaly = 0 AND f.rating IS NOT NULL AND f.review_count IS NOT NULL
)
SELECT
  main_category,
  product_segment,
  COUNT(*)                                                           AS product_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY main_category), 2)
    AS pct_within_category,
  ROUND(AVG(actual_price), 2)                                        AS avg_price,
  ROUND(AVG(discount_pct), 2)                                        AS avg_discount_pct
FROM segmented
GROUP BY main_category, product_segment;


-- ============================================================================
-- FASE 7 — DATA QUALITY REPORT MART (Halaman 4 — Transparency Report)
-- Mempertanggungjawabkan apa yang dibuang/diflag dari raw -> fact,
-- supaya proses cleaning transparan ke stakeholder, bukan disembunyikan.
-- ============================================================================

CREATE OR REPLACE TABLE `product_analiysis.mart_data_quality` AS
SELECT
  main_category,
  COUNT(*)                                    AS total_rows_staged,
  COUNTIF(is_duplicate = 1)                   AS duplicate_rows,
  ROUND(COUNTIF(is_duplicate = 1) * 100.0 / COUNT(*), 2)      AS duplicate_pct,
  COUNTIF(flag_missing_rating = 1)            AS missing_rating_rows,
  ROUND(COUNTIF(flag_missing_rating = 1) * 100.0 / COUNT(*), 2) AS missing_rating_pct,
  COUNTIF(flag_price_anomaly = 1)             AS price_anomaly_rows,
  COUNTIF(flag_price_outlier = 1)             AS price_outlier_rows
FROM `product_analiysis.stg_amazon_products_quality`
GROUP BY main_category
ORDER BY total_rows_staged DESC;

-- 7.1 Ringkasan keseluruhan (satu baris, untuk KPI card)
SELECT
  (SELECT COUNT(*) FROM `product_analiysis.amazon_product`)              AS raw_row_count,
  (SELECT COUNT(*) FROM `product_analiysis.stg_amazon_products_quality`) AS staged_row_count,
  (SELECT COUNT(*) FROM `product_analiysis.fact_products_clean`)         AS final_clean_row_count,
  (SELECT COUNTIF(is_duplicate = 1) FROM `product_analiysis.stg_amazon_products_quality`)
    AS total_duplicates_removed;

-- ============================================================================
-- END OF PIPELINE
-- Lanjutan: buka Amazon_Products_Final_Analysis.ipynb untuk EDA,
-- uji statistik inferensial, segmentasi, dan business insight final.
-- ============================================================================
