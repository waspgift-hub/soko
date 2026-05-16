import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/status_service.dart';
import '../../extensions/context_tr.dart';
import '../../utils/helpers.dart';

class AddStatusScreen extends StatefulWidget {
  const AddStatusScreen({super.key});

  @override
  State<AddStatusScreen> createState() => _AddStatusScreenState();
}

class _AddStatusScreenState extends State<AddStatusScreen> {
  final StatusService _statusService = StatusService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();

  int _selectedTab = 0;
  bool _isPosting = false;
  File? _selectedMedia;
  Color _selectedBgColor = const Color(0xFF2D6A4F);
  double _fontSize = 28;

  static const List<Color> _bgColors = [
    Color(0xFF2D6A4F),
    Color(0xFF40916C),
    Color(0xFF1B4332),
    Color(0xFF52796F),
    Color(0xFF84A98C),
    Color(0xFF354F52),
    Color(0xFF6B705C),
    Color(0xFFA5A58D),
    Color(0xFFBC6C25),
    Color(0xFF606C38),
    Color(0xFF283618),
    Color(0xFFDDA15E),
    Color(0xFF6D6875),
    Color(0xFFB5838D),
    Color(0xFFE5989B),
    Color(0xFF6B705C),
  ];

  @override
  void dispose() {
    _textController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImageGallery() async {
    try {
      final granted = await requestPermissionWithDialog(
        context,
        Permission.photos,
        'permission_photos',
      );
      if (!granted || !mounted) return;

      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        setState(() {
          _selectedMedia = File(image.path);
          _selectedTab = 1;
        });
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _pickImageCamera() async {
    try {
      final granted = await requestPermissionWithDialog(
        context,
        Permission.camera,
        'permission_camera',
      );
      if (!granted || !mounted) return;

      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null && mounted) {
        setState(() {
          _selectedMedia = File(image.path);
          _selectedTab = 1;
        });
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _pickVideo() async {
    try {
      final granted = await requestPermissionWithDialog(
        context,
        Permission.photos,
        'permission_photos',
      );
      if (!granted || !mounted) return;

      final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video != null && mounted) {
        setState(() {
          _selectedMedia = File(video.path);
          _selectedTab = 2;
        });
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.tr('status_error')}$message'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _postStatus() async {
    if (_isPosting) return;

    if (_selectedTab == 0 && _textController.text.trim().isEmpty) {
      _showError(context.tr('write_status'));
      return;
    }

    setState(() => _isPosting = true);

    try {
      switch (_selectedTab) {
        case 0:
          await _statusService.postTextStatus(_textController.text.trim());
          break;
        case 1:
          if (_selectedMedia != null) {
            await _statusService.postImageStatus(
              _selectedMedia!,
              caption: _captionController.text.trim().isEmpty
                  ? null
                  : _captionController.text.trim(),
            );
          }
          break;
        case 2:
          if (_selectedMedia != null) {
            await _statusService.postVideoStatus(
              _selectedMedia!,
              caption: _captionController.text.trim().isEmpty
                  ? null
                  : _captionController.text.trim(),
            );
          }
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('status_posted')),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _isPosting = false);
      }
    }
  }

  void _showMediaOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF2D6A4F)),
              title: Text(context.tr('gallery')),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2D6A4F)),
              title: Text(context.tr('camera_label')),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Color(0xFF2D6A4F)),
              title: Text(context.tr('video_status')),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.tr('add_status'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_isPosting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _postStatus,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildTabBar(cs),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildTabItem(0, Icons.text_fields, context.tr('text_status')),
          const SizedBox(width: 12),
          _buildTabItem(1, Icons.photo, context.tr('photo_status')),
          const SizedBox(width: 12),
          _buildTabItem(2, Icons.videocam, context.tr('video_status')),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (index != 0 && _selectedMedia == null) {
            _showMediaOptions();
          } else {
            setState(() => _selectedTab = index);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2D6A4F)
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedTab) {
      case 0:
        return _buildTextStatusEditor();
      case 1:
        return _buildMediaStatusEditor(isVideo: false);
      case 2:
        return _buildMediaStatusEditor(isVideo: true);
      default:
        return _buildTextStatusEditor();
    }
  }

  Widget _buildTextStatusEditor() {
    return Container(
      color: _selectedBgColor,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  autofocus: true,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _fontSize,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Andika hali yako...',
                    hintStyle: TextStyle(
                      color: Colors.white54,
                      fontSize: 28,
                    ),
                    border: InputBorder.none,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          _buildTextControls(),
        ],
      ),
    );
  }

  Widget _buildTextControls() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${context.tr('choose_background')}:',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _bgColors.length,
                    itemBuilder: (context, index) {
                      final color = _bgColors[index];
                      final isSelected = _selectedBgColor == color;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedBgColor = color),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${context.tr('font_size')}:',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 18,
                  max: 42,
                  divisions: 4,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white.withValues(alpha: 0.3),
                  label: _fontSize < 24
                      ? context.tr('small')
                      : (_fontSize < 32
                          ? context.tr('medium')
                          : context.tr('large')),
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaStatusEditor({required bool isVideo}) {
    return Column(
      children: [
        if (_selectedMedia != null)
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: isVideo
                      ? _buildVideoPreview()
                      : Image.file(
                          _selectedMedia!,
                          fit: BoxFit.contain,
                          width: double.infinity,
                        ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedMedia = null;
                        _selectedTab = 0;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: GestureDetector(
              onTap: _showMediaOptions,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam : Icons.photo_library,
                      size: 72,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isVideo
                          ? context.tr('video_status')
                          : context.tr('photo_status'),
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('tap_to_view'),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_selectedMedia != null) _buildCaptionInput(),
      ],
    );
  }

  Widget _buildVideoPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.file(
          _selectedMedia!,
          fit: BoxFit.contain,
          width: double.infinity,
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: 40,
          ),
        ),
      ],
    );
  }

  Widget _buildCaptionInput() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _captionController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: context.tr('status_caption'),
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2D6A4F)),
          ),
        ),
        maxLines: 2,
      ),
    );
  }
}
