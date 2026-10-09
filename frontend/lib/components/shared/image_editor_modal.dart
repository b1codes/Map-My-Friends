import 'dart:typed_data';
import 'dart:ui' as ui; // For ImageByteFormat
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // For RenderRepaintBoundary
import 'glass_surfaces.dart';
import 'glass_header.dart';

class ImageEditorModal extends StatefulWidget {
  final Uint8List imageBytes;
  final bool isCircular; // Useful to show circle overlay for profile pics

  const ImageEditorModal({
    super.key,
    required this.imageBytes,
    this.isCircular = true,
  });

  @override
  State<ImageEditorModal> createState() => _ImageEditorModalState();
}

class _ImageEditorModalState extends State<ImageEditorModal> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  final TransformationController _transformationController =
      TransformationController();

  Future<void> _saveImage() async {
    try {
      RenderRepaintBoundary? boundary =
          _repaintBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) return;

      // Capture the image from the boundary
      // We might want to capture at a higher pixel ratio for better quality
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      Uint8List? pngBytes = byteData?.buffer.asUint8List();

      if (pngBytes != null && mounted) {
        Navigator.pop(context, pngBytes);
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      if (mounted) {
        GlassToast.show(context, 'Error saving image: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The editor stays black on purpose: an image is being judged, and any
    // colour behind it lies about what the crop will look like. It is the one
    // surface in the app that is deliberately not made of glass.
    return BackdropGroup(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: <Widget>[
            GlassHeader(
              title: 'Edit Image',
              actions: <HeaderAction>[
                HeaderAction(
                  icon: Icons.check,
                  label: 'Save',
                  onPressed: _saveImage,
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // The cropping area
                          RepaintBoundary(
                            key: _repaintBoundaryKey,
                            child: Container(
                              width: 300,
                              height: 300,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                // If circular, we clip it so the saved image is also circular?
                                // Actually, standard practice is to save the square and let the UI mask it.
                                // But if we want to save exactly what is seen...
                                // Let's keep it simple: We capture the square area.
                              ),
                              child: ClipRect(
                                child: InteractiveViewer(
                                  transformationController:
                                      _transformationController,
                                  minScale: 0.5,
                                  maxScale: 4.0,
                                  boundaryMargin: const EdgeInsets.all(
                                    double.infinity,
                                  ),
                                  child: Image.memory(
                                    widget.imageBytes,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Overlay to indicate the crop area (this is NOT captured)
                          IgnorePointer(
                            child: Container(
                              width: 300,
                              height: 300,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                shape: widget.isCircular
                                    ? BoxShape.circle
                                    : BoxShape.rectangle,
                              ),
                            ),
                          ),

                          // Helper text
                          const Positioned(
                            bottom: 20,
                            child: Text(
                              'Pinch to zoom, drag to move',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
