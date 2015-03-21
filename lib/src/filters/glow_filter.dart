library stagexl.filters.glow;

import 'dart:math' hide Point, Rectangle;
import 'dart:html' show ImageData;
import 'dart:typed_data';
import 'dart:web_gl' as gl;

import '../display.dart';
import '../engine.dart';
import '../geom.dart';
import '../internal/filter_helpers.dart';
import '../internal/tools.dart';

class GlowFilter extends BitmapFilter {

  int _color;
  int _blurX;
  int _blurY;
  int _quality;

  bool knockout;
  bool hideObject;

  final List<int> _renderPassSources = new List<int>();
  final List<int> _renderPassTargets = new List<int>();

  GlowFilter([
    int color = 0xFF000000,
    int blurX = 4, int blurY = 4, int quality = 1,
    bool knockout = false, bool hideObject = false]) {

    this.color = color;
    this.blurX = blurX;
    this.blurY = blurY;
    this.quality = quality;
    this.knockout = knockout;
    this.hideObject = hideObject;
  }

  //---------------------------------------------------------------------------

  BitmapFilter clone() {
    return new GlowFilter(color, blurX, blurY, quality, knockout,  hideObject);
  }

  Rectangle<int> get overlap {
    return new Rectangle<int>(-blurX, -blurY, 2 * blurX, 2 * blurY);
  }

  List<int> get renderPassSources => _renderPassSources;
  List<int> get renderPassTargets => _renderPassTargets;

  //---------------------------------------------------------------------------

  /// The color of the glow.

  int get color => _color;

  set color(int value) {
    _color = value;
  }

  /// The horizontal blur radius in the range from 0 to 64.

  int get blurX => _blurX;

  set blurX(int value) {
    RangeError.checkValueInInterval(value, 0, 64);
    _blurX = value;
  }

  /// The vertical blur radius in the range from 0 to 64.

  int get blurY => _blurY;

  set blurY(int value) {
    RangeError.checkValueInInterval(value, 0, 64);
    _blurY = value;
  }

  /// The quality of the glow in the range from 1 to 5.
  /// A small value is sufficent for small blur radii, a high blur
  /// radius may require a heigher quality setting.

  int get quality => _quality;

  set quality(int value) {

    RangeError.checkValueInInterval(value, 1, 5);

    _quality = value;
    _renderPassSources.clear();
    _renderPassTargets.clear();

    for(int i = 0; i < value; i++) {
      _renderPassSources.add(i * 2 + 0);
      _renderPassSources.add(i * 2 + 1);
      _renderPassTargets.add(i * 2 + 1);
      _renderPassTargets.add(i * 2 + 2);
    }

    _renderPassSources.add(0);
    _renderPassTargets.add(value * 2);
  }

  //---------------------------------------------------------------------------

  void apply(BitmapData bitmapData, [Rectangle<int> rectangle]) {

    RenderTextureQuad renderTextureQuad = rectangle == null
        ? bitmapData.renderTextureQuad
        : bitmapData.renderTextureQuad.cut(rectangle);

    ImageData sourceImageData =
        this.hideObject == false || this.knockout ? renderTextureQuad.getImageData() : null;

    ImageData imageData = renderTextureQuad.getImageData();
    List<int> data = imageData.data;
    int width = ensureInt(imageData.width);
    int height = ensureInt(imageData.height);

    num pixelRatio = renderTextureQuad.renderTexture.storePixelRatio;
    int blurX = (this.blurX * pixelRatio).round();
    int blurY = (this.blurY * pixelRatio).round();
    int alphaChannel = BitmapDataChannel.getCanvasIndex(BitmapDataChannel.ALPHA);
    int stride = width * 4;

    for (int x = 0; x < width; x++) {
      blur(data, x * 4 + alphaChannel, height, stride, blurY);
    }

    for (int y = 0; y < height; y++) {
      blur(data, y * stride + alphaChannel, width, 4, blurX);
    }

    if (this.knockout) {
      setColorKnockout(data, this.color, sourceImageData.data);
    } else if (this.hideObject) {
      setColor(data, this.color);
    } else {
      setColorBlend(data, this.color, sourceImageData.data);
    }

    renderTextureQuad.putImageData(imageData);
  }

  //---------------------------------------------------------------------------

  void renderFilter(RenderState renderState,
                    RenderTextureQuad renderTextureQuad, int pass) {

    RenderContextWebGL renderContext = renderState.renderContext;
    RenderTexture renderTexture = renderTextureQuad.renderTexture;
    int passCount = _renderPassSources.length;

    if (pass == passCount - 1) {

      if (!this.knockout && !this.hideObject) {
        renderState.renderQuad(renderTextureQuad);
      }

    } else {

      GlowFilterProgram renderProgram = renderContext.getRenderProgram(
          r"$GlowFilterProgram", () => new GlowFilterProgram());

      num scale = pow(0.5, pass >> 1);
      num alpha = pass == passCount - 2 ? renderState.globalAlpha : 1.0;
      int color = pass == passCount - 2 ? this.color : this.color | 0xFF000000;

      num radiusX = scale * blurX / renderTexture.width;
      num radiusY = scale * blurY / renderTexture.height;

      radiusX = pass.isEven ? radiusX : 0.0;
      radiusY = pass.isEven ? 0.0 : radiusY;

      renderContext.activateRenderProgram(renderProgram);
      renderContext.activateRenderTexture(renderTexture);
      renderProgram.renderGlowFilterQuad(
          renderState, renderTextureQuad,
          color, alpha, radiusX, radiusY);
    }
  }
}

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------

class GlowFilterProgram extends RenderProgram {

  RenderBufferVertex _renderBufferVertex;

  //---------------------------------------------------------------------------
  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexTextCoord:  Float32(u), Float32(v)
  //---------------------------------------------------------------------------

  String get vertexShaderSource => """

    uniform mat4 uProjectionMatrix;
    uniform vec2 uRadius;

    attribute vec2 aPosition;
    attribute vec2 aTexCoord;

    varying vec2 vBlurCoords[7];

    void main() {
      vBlurCoords[0] = aTexCoord - uRadius * 1.2;
      vBlurCoords[1] = aTexCoord - uRadius * 0.8;
      vBlurCoords[2] = aTexCoord - uRadius * 0.4;
      vBlurCoords[3] = aTexCoord;
      vBlurCoords[4] = aTexCoord + uRadius * 0.4;
      vBlurCoords[5] = aTexCoord + uRadius * 0.8;
      vBlurCoords[6] = aTexCoord + uRadius * 1.2;
      gl_Position = vec4(aPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    """;

  String get fragmentShaderSource => """
    
    precision mediump float;
    uniform sampler2D uSampler;
    uniform vec4 uColor;

    varying vec2 vBlurCoords[7];

    void main() {
      float alpha = 0.0;
      alpha += texture2D(uSampler, vBlurCoords[0]).a * 0.00443;
      alpha += texture2D(uSampler, vBlurCoords[1]).a * 0.05399;
      alpha += texture2D(uSampler, vBlurCoords[2]).a * 0.24197;
      alpha += texture2D(uSampler, vBlurCoords[3]).a * 0.39894;
      alpha += texture2D(uSampler, vBlurCoords[4]).a * 0.24197;
      alpha += texture2D(uSampler, vBlurCoords[5]).a * 0.05399;
      alpha += texture2D(uSampler, vBlurCoords[6]).a * 0.00443;
      alpha *= uColor.a;
      gl_FragColor = vec4(uColor.rgb * alpha, alpha);
    }
    """;

  //---------------------------------------------------------------------------

  @override
  void activate(RenderContextWebGL renderContext) {

    super.activate(renderContext);

    _renderBufferVertex = renderContext.renderBufferVertex;
    _renderBufferVertex.activate(renderContext);
    _renderBufferVertex.bindAttribute(attributes["aPosition"], 2, 16, 0);
    _renderBufferVertex.bindAttribute(attributes["aTexCoord"], 2, 16, 8);
  }

  //---------------------------------------------------------------------------

  void renderGlowFilterQuad(
      RenderState renderState, RenderTextureQuad renderTextureQuad,
      int color, num alpha, num radiusX, num radiusY) {

    int width = renderTextureQuad.textureWidth;
    int height = renderTextureQuad.textureHeight;
    int offsetX = renderTextureQuad.offsetX;
    int offsetY = renderTextureQuad.offsetY;
    Float32List uvList = renderTextureQuad.uvList;
    Matrix matrix = renderState.globalMatrix;

    num r = colorGetR(color) / 255.0;
    num g = colorGetG(color) / 255.0;
    num b = colorGetB(color) / 255.0;
    num a = colorGetA(color) / 255.0 * alpha;

    renderingContext.uniform2f(uniforms["uRadius"], radiusX, radiusY);
    renderingContext.uniform4f(uniforms["uColor"], r, g, b, a);
    renderingContext.uniform1i(uniforms["uSampler"], 0);

    // Calculate the 4 vertices of the RenderTextureQuad

    var vxData = _renderBufferVertex.data;
    if (vxData == null) return;
    if (vxData.length < 16) return;

    for(int vertex = 0, index = 0; vertex < 4; vertex++, index += 4) {

      int x = offsetX + (vertex == 1 || vertex == 2 ? width  : 0);
      int y = offsetY + (vertex == 2 || vertex == 3 ? height : 0);

      if (index > vxData.length - 4) return; // dart2js_hint

      vxData[index + 0] = matrix.tx + x * matrix.a + y * matrix.c;
      vxData[index + 1] = matrix.ty + x * matrix.b + y * matrix.d;
      vxData[index + 2] = uvList[vertex + vertex + 0];
      vxData[index + 3] = uvList[vertex + vertex + 1];
    }

    // Update vertex buffer and render quad

    _renderBufferVertex.update(0, 16);
    renderingContext.drawArrays(gl.TRIANGLE_FAN, 0, 4);
  }
}

