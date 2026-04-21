# Tổng quan kiến trúc dự án GG.A

Dự án được xây dựng theo kiến trúc phân lớp (Layered Architecture) kết hợp với mô hình MVVM (Model-ViewModel-ViewModel) để đảm bảo tính tách biệt giữa giao diện và logic nghiệp vụ.

## Các công nghệ chính
- **Flutter**: Framework chính.
- **Supabase**: Quản lý cơ sở dữ liệu Metadata (thông tin ảnh, tỷ lệ khung hình) và cập nhật thời gian thực (Realtime).
- **GitHub API**: Lưu trữ file ảnh vật lý và quản lý các bản phát hành (releases) của ứng dụng.
- **Shared Preferences**: Lưu trữ cấu hình người dùng (theme, cài đặt).

## Cấu trúc thư mục chính
- `data/`: Chứa các lớp dữ liệu, dịch vụ API và kho lưu trữ (Repositories).
- `logic/viewmodels/`: Chứa các lớp quản lý trạng thái và logic nghiệp vụ.
- `screens/` & `tabs/`: Chứa giao diện chính của ứng dụng.
- `widgets/`: Các thành phần giao diện dùng chung.
- `utils/`: Các công cụ hỗ trợ (Haptics, Update Manager, Migration).
