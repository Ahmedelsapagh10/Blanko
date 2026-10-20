import 'dart:convert';
import 'dart:typed_data';

// Controlled 64 × 32 opaque RGB bands; no platform asset-loader dependency.
Uint8List imageTestPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAYAAACinX6EAAAAUElEQVR4nO3QMQ0AIAwAsCnhRgQiuBGLpjkAE+whPWqgkX2cCn3PEm3lUyFAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgT8H3AB0td4j7Yk1bYAAAAASUVORK5CYII=',
);
