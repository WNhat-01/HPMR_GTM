# Học phần mở rộng – Giải tích mạch (EE2033, HK261 – HCMUT)

**Đề 5:** Phân tích mạch RLC bằng chuỗi Fourier và mô phỏng với nguồn áp chỉnh lưu bán kỳ.  
**Bộ thông số cá thể hóa:** $N_1 = 2,\; N_2 = 3,\; N_3 = 1$ ($E_m = 19\text{ V},\; f_0 = 80\text{ Hz},\; R = 28\ \Omega,\; L = 14\text{ mH},\; C = 18\ \mu\text{F}$).

## Cấu trúc thư mục

```text
.
├── Đề tài.pdf                  # Đề bài gốc của môn học
├── sim/
│   ├── De5_RLC_Fourier.asc     # File mô phỏng LTspice duy nhất (Câu d + Câu e)
│   ├── De5_RLC_Fourier.net     # Netlist sinh từ LTspice
│   └── De5_RLC_Fourier.log     # Kết quả đo tự động (.meas) từ LTspice
├── scripts/
│   ├── verify_de5.ps1          # Kiểm chứng tích phân Fourier, |H|, Parseval RMS
│   └── export_plot_data.ps1    # Trích dữ liệu LTspice .raw & tính RMSE/NRMSE
└── report/
    ├── main.tex                # File LaTeX chính (compile bằng XeLaTeX)
    ├── main.pdf                # Báo cáo PDF đã biên dịch
    ├── chapters/               # Các chương báo cáo (00_cover .. 05_conclusion)
    └── data/                   # Dữ liệu đồ thị vector (pgfplots)
```

## Hướng dẫn cho thành viên nhóm

1. **Chỉnh sửa thông tin thành viên & GVHD:** mở `report/chapters/00_cover.tex`, thay các dòng `[...]` màu đỏ.
2. **Biên dịch báo cáo PDF:** mở thư mục bằng **VS Code** (cài extension `LaTeX Workshop`, đã cấu hình sẵn `XeLaTeX` trong `.vscode/settings.json`) hoặc chạy lệnh trong `report/`:
   ```powershell
   xelatex -interaction=nonstopmode main.tex
   xelatex -interaction=nonstopmode main.tex
   ```
3. **Chạy mô phỏng LTspice:** mở `sim/De5_RLC_Fourier.asc` bằng LTspice và nhấn **Run**; xem kết quả đo tự động trong `View -> SPICE Error Log`.
