part of stagexl.drawing;

/// The base class for all graphics commands

abstract class GraphicsCommand {

  Graphics _graphics = null;

  Graphics get graphics => _graphics;

  void updateContext(GraphicsContext context);
  void invalidate() => _graphics?._invalidate();

  void _setGraphics(Graphics graphics) {
    if (_graphics != null && graphics != null) {
      throw new ArgumentError("Command is already assigned to graphics.");
    } else {
      _graphics = graphics;
    }
  }
}

