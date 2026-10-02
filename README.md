# 🛒 Amazon E-Commerce Sales Strategy: Pricing & Product Segmentation Analysis

![Looker Studio](https://img.shields.io/badge/Looker_Studio-4285F4?style=for-the-badge&logo=google&logoColor=white)
![Google BigQuery](https://img.shields.io/badge/Google_BigQuery-669DF6?style=for-the-badge&logo=google-cloud&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)

> **Proyek Analisis Data End-to-End** yang mengubah lebih dari 500.000 data *listing* mentah Amazon India menjadi wawasan strategis yang dapat ditindaklanjuti untuk tim Pricing, Merchandising, dan Marketing.

*(Ganti teks ini dengan link menuju Dashboard Looker Studio interaktif Anda)*  
👉 **[Lihat Live Dashboard di Looker Studio](https://lookerstudio.google.com/...)**

---

## 📌 1. Business Problem & Objective
Jutaan produk beredar di Amazon dengan variasi harga dan diskon yang sangat beragam. Seringkali penjual dan tim strategi platform berasumsi bahwa **"diskon besar sama dengan produk laris"** dan **"harga mahal berarti rating tinggi"**. Promosi sering dilakukan tanpa dasar data yang kuat.

**Tujuan Proyek:**
1. Membuktikan secara statistik apakah strategi diskon benar-benar berkorelasi dengan traksi pasar (popularitas).
2. Mengklasifikasikan produk ke dalam **4 Segmen Utama** untuk mengoptimalkan anggaran promosi (Ads) dan manajemen katalog.

---

## 📊 2. Key Business Insights

### Mitos Diskon Terbantahkan
Melalui uji korelasi *Spearman* yang distratifikasi per kategori dan dikoreksi dengan *Benjamini-Hochberg FDR*, ditemukan bahwa **diskon tinggi tidak menjamin popularitas produk secara universal**. 
* Pada kategori `home_kitchen`, diskon memang mendorong interaksi (rho = 0.413).
* Namun pada kategori `electronics`, hubungannya justru **negatif** (rho = -0.141). Pembeli elektronik lebih mengutamakan spesifikasi dan merek dibandingkan potongan harga.

### Matriks Segmentasi Produk
Alih-alih menganalisis produk secara individual, ratusan ribu produk dipecah ke dalam 4 kuadran strategis berdasarkan *Rating* (Kualitas) dan *Review Count* (Popularitas) relatif terhadap median masing-masing kategori:

![Distribusi Segmen Produk](assets/segmentation_chart.png)  
*(Ganti placeholder gambar di atas dengan screenshot grafik batang segmentasi produk Anda)*

1. 🌟 **Best Seller (26.7%):** Produk unggulan dengan rating dan popularitas di atas rata-rata.
2. 💎 **Hidden Gem (25.4%):** Kualitas terbukti tinggi (Rating > Median), namun kurang terekspos (Review < Median).
3. ⚠️ **Overhyped (23.4%):** Produk sangat populer namun banyak mendapat keluhan (Rating < Median).
4. 🗑️ **Risky (24.5%):** Produk dengan performa buruk secara kualitas maupun traksi.

---

## 💡 3. Actionable Recommendations

*   **Bagi Tim Marketing:** Stop membakar anggaran iklan untuk produk yang sudah *Best Seller* atau *Risky*. Alihkan sebagian besar anggaran Ads untuk mempromosikan produk **Hidden Gem**. Kualitas mereka sudah tervalidasi oleh pembeli awal; mereka hanya butuh lebih banyak eksposur.
*   **Bagi Tim Pricing:** Hentikan strategi "Diskon Pukul Rata". Untuk kategori *Electronics*, bersainglah di aspek fitur dan garansi, bukan banting harga. 
*   **Bagi Tim Merchandising:** Segera lakukan audit pada 23.4% produk di segmen **Overhyped**. Karena produk ini sering dilihat pengunjung, rating yang rendah dapat merusak citra *marketplace* secara keseluruhan.

---

## ⚙️ 4. Data Architecture & Pipeline

Proyek ini menggunakan arsitektur ETL terstruktur untuk memastikan *data governance* yang baik sebelum divisualisasikan:

1.  **Extract & Load:** Mengimpor dataset raw (551k+ baris) ke dalam **Google BigQuery**.
2.  **Transform (SQL):** 
    *   *Staging Layer:* Pembersihan *Null*, *casting* tipe data numerik, ekstraksi `ASIN` sebagai *primary key*.
    *   *Data Quality Layer:* Deteksi duplikat, anomali harga (harga = 0), dan identifikasi outlier.
    *   *Mart Layer:* Pembuatan tabel agregasi khusus (seperti `mart_category_summary` dan `mart_segment_distribution`) untuk performa dashboard yang ringan.
3.  **Statistical Analysis (Python):** Menggunakan `Google Colab` dengan *SciPy* dan *Statsmodels* untuk menjalankan uji inferensial (Spearman, Kruskal-Wallis, Mann-Whitney U Test) dari data yang ditarik via BigQuery API.
4.  **Visualize:** Menghubungkan *Mart Layer* ke **Looker Studio** untuk *dashboard* interaktif.

---

## 📂 5. Repository Structure

```text
├── assets/
│   ├── dashboard_screenshot.png       # Tampilan Looker Studio
│   └── segmentation_chart.png         # Grafik segmentasi Python
├── notebooks/
│   └── Amazon_Products_Final_Analysis.ipynb  # Script EDA & Uji Statistik (SciPy)
├── reports/
│   ├── Amazon_Products_Analysis_Report.pdf   # Laporan Eksekutif Lengkap
│   └── business_insight_summary.txt          # Ringkasan insight teks
├── sql/
│   └── amazon_products_pipeline.sql   # Script ETL BigQuery (Staging s/d Mart)
└── README.md
