import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

/// Офлайн-распознавание текста с фото (Tesseract, русский язык).
/// Нужен файл assets/tessdata/rus.traineddata (см. SCHEDULE.md).
Future<String> recognizeText(String imagePath) =>
    FlutterTesseractOcr.extractText(
      imagePath,
      language: 'rus',
      args: {'psm': '6', 'preserve_interword_spaces': '1'},
    );
