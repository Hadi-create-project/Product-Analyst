# 🛒 Amazon E-Commerce Sales Strategy: Pricing & Product Segmentation Analysis

![Looker Studio](https://img.shields.io/badge/Looker_Studio-4285F4?style=for-the-badge&logo=google&logoColor=white)
![Google BigQuery](https://img.shields.io/badge/Google_BigQuery-669DF6?style=for-the-badge&logo=google-cloud&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-F29111?style=for-the-badge&logo=postgresql&logoColor=white)

> **Proyek Analisis Data End-to-End** yang memproses data katalog raksasa Amazon menjadi wawasan strategis untuk mengoptimalkan anggaran promosi, menghentikan perang harga yang tidak efektif, dan memetakan segmentasi produk bagi tim Pricing, Merchandising, dan Marketing[cite: 4, 16].

### 🔗 Quick Links
*   📈 **[Live Dashboard - Looker Studio](MASUKKAN_LINK_LOOKER_STUDIO_ANDA_DI_SINI)**
*   📄 **[Executive Summary Report (PDF)](reports/Amazon_Products_Analysis_Report.pdf)**
*   📓 **[Statistical Analysis Notebook (Colab)](notebooks/Amazon_Products_Final_Analysis.ipynb)**
*   🗄️ **[Original Dataset (Kaggle)](https://www.kaggle.com/datasets/lokeshparab/amazon-products-dataset/data?select=Amazon-Products.csv)**

---

## 📌 1. Konteks Bisnis & Pernyataan Masalah

Amazon memiliki jutaan *listing* produk lintas kategori dengan variasi harga, diskon, dan tingkat kepuasan pelanggan yang sangat tajam[cite: 5]. Dalam ekosistem yang sekompetitif ini, penjual dan tim strategi platform seringkali mengambil keputusan berdasarkan insting atau asumsi yang bias, seperti:
*   *"Memberikan diskon besar otomatis akan membuat produk laris manis."*
*   *"Produk dengan ulasan terbanyak pasti memiliki kualitas (rating) yang paling bagus."*

Praktik promosi yang dilakukan tanpa dasar data yang kuat ini seringkali berujung pada **inefisiensi anggaran iklan (*Ad Spend*)** dan **perang harga (*price war*)** yang pada akhirnya hanya menggerus margin keuntungan tanpa memberikan dampak loyalitas pelanggan yang berarti.

**Tujuan Analisis:**
1. Menguji kebenaran asumsi pasar melalui uji statistik: Apakah strategi diskon benar-benar mendorong traksi popularitas di semua kategori?[cite: 5]
2. Membangun kerangka segmentasi produk untuk mengidentifikasi produk berpotensi tinggi yang kurang terekspos (*Hidden Gems*) dan memisahkan produk berisiko tinggi (*Overhyped*)[cite: 6].

---

## ⚙️ 2. Metodologi & Alur Proses Data

Proyek ini tidak sekadar membuat visualisasi, melainkan membangun *data pipeline* tingkat produksi yang memastikan tata kelola dan validitas data sebelum analisis dilakukan[cite: 19].

1.  **Data Extraction & Profiling (BigQuery SQL):** Mengimpor dataset mentah dan melakukan pengukuran anomali awal. Ditemukan 6.0% data kehilangan informasi rating, 2.9% baris duplikat, dan 0.5% anomali harga (harga = 0)[cite: 8].
2.  **Data Cleaning & Deduplication (BigQuery SQL):** 
    *   Mengekstraksi `ASIN` dari URL sebagai pengidentifikasi unik produk[cite: 8].
    *   Menghapus 336 baris duplikat dan menandai anomali harga, menyisakan **11.149 produk unik** siap pakai[cite: 8, 14].
3.  **Feature Engineering (BigQuery SQL):** Menciptakan metrik bisnis baru seperti `discount_pct` (persentase diskon) dan membagi harga ke dalam kelompok `price_bucket` (Budget, Mid, Premium) untuk tiap sub-kategori[cite: 8].
4.  **Exploratory Data Analysis & Statistical Inference (Python):** Memindahkan agregasi data ke Google Colab. Melakukan uji korelasi *Spearman* yang distratifikasi per kategori produk dan dikoreksi dengan metode *Benjamini-Hochberg False Discovery Rate (FDR)* guna menghindari bias konklusi lintas kategori[cite: 11, 21].
5.  **Actionable Dashboarding (Looker Studio):** Menghubungkan *Mart Layer* BigQuery ke Looker Studio untuk memantau metrik secara interaktif[cite: 19, 21].

---

## 📊 3. Temuan Utama & Wawasan Bisnis

### A. Mitos Diskon Terbantahkan (The Discount Illusion)
Banyak penjual membakar uang melalui diskon besar demi mendapatkan ulasan terbanyak. Namun, uji statistik membuktikan bahwa **korelasi antara diskon dan popularitas tidak berlaku seragam di semua kategori**[cite: 12].
*   Di kategori `home_kitchen` dan `appliances`, diskon terbukti signifikan mendorong popularitas (rho = 0.413 dan 0.327)[cite: 11]. Diskon agresif di kategori ini terbukti efektif[cite: 15].
*   Sebaliknya, pada kategori `electronics`, hubungannya berbalik menjadi **negatif** (rho = -0.141)[cite: 12]. Pembeli barang elektronik lebih sensitif terhadap spesifikasi teknis dan kepercayaan merek dibandingkan sekadar potongan harga[cite: 15].

### B. Matriks Kualitas vs. Popularitas (Product Quadrants)
Membandingkan Rating (Kualitas) dan Jumlah Ulasan (Engagement/Popularitas) terhadap nilai tengah (median) dari masing-masing kategori[cite: 13]. Pemetaan ini menghasilkan 4 kuadran produk:

1.  🌟 **Best Seller (26.7%):** Bintang pasar. Rating memuaskan dan sangat populer[cite: 13, 14].
2.  💎 **Hidden Gem (25.4%):** Kualitas sangat tinggi (Rating > Median) namun jarang dibeli/diulas (Review < Median). Ini adalah tambang emas yang belum tergali[cite: 13].
3.  ⚠️ **Overhyped (23.4%):** Sangat populer dan sering dibeli, namun kualitas aslinya mengecewakan pembeli (Rating < Median)[cite: 13, 14].
4.  🗑️ **Risky (24.5%):** Kualitas buruk dan sepi peminat[cite: 13].

---

## 💡 4. Rekomendasi Strategis Berbasis Data

*   **Untuk Tim Marketing (Optimasi Ads):** Hentikan alokasi iklan untuk produk di kuadran *Best Seller* (sudah memiliki *traffic* organik yang kuat) dan kuadran *Risky*[cite: 16]. Pindahkan 70% anggaran *Campaign* untuk memberikan eksposur maksimal pada produk **Hidden Gem**. Mereka sudah terbukti memuaskan pembeli awal, hanya butuh dorongan visibilitas[cite: 16].
*   **Untuk Tim Pricing (Strategi Harga):** Tinggalkan metode "Diskon Pukul Rata". Sesuaikan agresivitas diskon berdasarkan sensitivitas kategori. Fokuskan strategi promosi diskon pada *Home Kitchen*, dan gunakan strategi *Value-Add* (seperti garansi ekstra atau *bundling*) untuk kategori *Electronics*[cite: 16].
*   **Untuk Tim Merchandising & Quality Control:** Prioritaskan investigasi dan audit segera pada 23.4% produk di segmen **Overhyped**[cite: 14, 16]. Karena produk ini sering muncul di pencarian teratas, akumulasi ulasan yang buruk dapat merusak tingkat kepercayaan konsumen terhadap keseluruhan platform[cite: 15, 17].

---

## 📈 5. Proyeksi Dampak Bisnis (Expected Impact)

Penerapan rekomendasi dari analisis ini diproyeksikan akan memberikan dampak langsung pada fundamental bisnis platform:
1.  **Efisiensi Anggaran (Cost Optimization):** Menghindari pembakaran uang pada diskon yang tidak relevan di kategori *Electronics*, serta menghentikan kebocoran *Ad Spend* pada produk berkualitas rendah[cite: 17].
2.  **Pertumbuhan Margin Organik (Revenue Growth):** Menaikkan status ratusan produk *Hidden Gem* menjadi *Best Seller* baru tanpa harus mengorbankan margin melalui diskon harga[cite: 17].
3.  **Manajemen Reputasi Jangka Panjang:** Mencegah penurunan retensi pelanggan dengan mendeteksi dini produk *Overhyped* sebelum ulasan negatif merusak metrik kepuasan pembeli (*Customer Satisfaction*) platform[cite: 15, 17].

---

*Dataset provided by Lokesh Parab via Kaggle.*
