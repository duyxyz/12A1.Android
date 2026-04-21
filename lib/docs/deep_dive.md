# Tài liệu Chuyên sâu: Nguyên lý hoạt động của GG.A

Tài liệu này giải thích chi tiết cách các tệp tin phối hợp với nhau để vận hành ứng dụng.

## 1. Luồng Khởi động và Hiển thị (Startup & Data Flow)
- **main.dart**: Khởi tạo `AppDependencies` (Container chứa singletons). Gọi `homeViewModel.loadImages()` ngay khi app mở.
- **HomeViewModel (loadImages)**: 
    - Đầu tiên đọc từ `ImageRepository.getCachedImages()` (SharedPreferences) để hiện ảnh ngay lập tức (giảm độ trễ).
    - Sau đó gọi `ImageRepository.getImages()` để lấy dữ liệu mới nhất từ mạng.
- **ImageRepository (getImages)**: 
    - Truy vấn Supabase (`fetchImageMetadata`) để lấy danh sách mô tả ảnh (tên, SHA, tỷ lệ khung hình). Công đoạn này rất nhanh vì metadata nhẹ.
    - Xây dựng URL trực tiếp đến GitHub Raw content cho từng ảnh.
    - Lưu metadata vào cache local.
- **HomeTab/FavoritesTab**: Nhận danh sách từ ViewModel và vẽ lên lưới bằng `SliverMasonryGrid`.

## 2. Nguyên lý Realtime (Cập nhật tức thì)
- **SupabaseApiService (getMetadataStream)**: Mở một kết nối liên tục (WebSocket) đến bảng `images` trên Supabase.
- **HomeViewModel (_setupRealtimeSubscription)**: Đăng ký lắng nghe Stream này. 
    - Nếu có bản ghi mới hoặc bị xóa: Gọi `loadImages(force: true)` để nạp lại danh sách.
    - Nếu chỉ đổi tỷ lệ khung hình (aspect ratio): Cập nhật trực tiếp vào danh sách hiện tại và gọi `notifyListeners()` để UI vẽ lại mà không cần tải lại file.

## 3. Luồng Tải ảnh (Upload Flow)
- **AddTab**: Sử dụng `ImagePicker` chọn ảnh. Nén ảnh sang **WebP** bằng `FlutterImageCompress` để tiết kiệm dung lượng (giảm từ vài MB xuống vài trăm KB).
- **ImageRepository (uploadImage)**:
    1. Gọi `reserveNextImageIndex` (Supabase): Tìm số thứ tự nhỏ nhất còn trống (Lấp đầy khoảng trống nếu có ảnh bị xóa).
    2. Gọi `githubApi.uploadImage`: Đẩy file nhị phân (base64) lên repo GitHub. GitHub trả về mã `sha`.
    3. Gọi `supabaseApi.upsertImageMetadata`: Lưu "chứng minh thư" của ảnh vào database kèm mã `sha` và kích thước ảnh.

## 4. Luồng Xóa ảnh (Delete Flow)
- **FullScreenImageViewer**: Yêu cầu `HomeViewModel.deleteImage`.
- **HomeViewModel**: Bật trạng thái `isLoading` để UI hiện overlay che chắn (tránh người dùng thao tác loạn xạ).
- **ImageRepository**:
    1. Xóa file trên GitHub bằng mã `sha`.
    2. Xóa metadata trên Supabase.
- **Sync**: Sau khi xóa, Realtime Stream sẽ báo về và ứng dụng tự động xóa ảnh đó khỏi màn hình chính.

## 5. Chi tiết nguyên lý từng File quan trọng
- **gallery_image.dart**: Không chỉ là chứa dữ liệu, nó chứa logic "thông minh" để tự suy luận `index` từ tên file (ví dụ cắt chuỗi `101_abc.webp` lấy `101`).
- **app_config_view_model.dart**: Sử dụng mẫu "Reactive Programming". Khi bạn đổi theme, nó lưu vào đĩa cứng đồng thời phát tín hiệu cho toàn bộ App đổi màu ngay lập tức.
- **github_api_service.dart**: Đóng gói các Header phức tạp của GitHub (Token, Content-Type, API Version) vào các hàm đơn giản.
- **expressive_loading_indicator.dart**: Sử dụng `AnimationController` để xoay tấm ảnh PNG theo một vòng tròn vô tận (0 đến 2π radian) mỗi 2 giây.
- **haptics.dart**: Cầu nối đến phần cứng rung của điện thoại. Nó kiểm tra cài đặt người dùng trước khi rung để đảm bảo sự tinh tế.
