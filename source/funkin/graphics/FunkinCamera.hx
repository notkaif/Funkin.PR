package funkin.graphics;

import flash.geom.ColorTransform;
import flixel.FlxCamera;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxMatrix;
import flixel.math.FlxRect;
import flixel.system.FlxAssets.FlxShader;
import funkin.graphics.shaders.RuntimeCustomBlendShader;
import funkin.graphics.framebuffer.FixedBitmapData;
import openfl.Lib;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display3D.textures.TextureBase;
import openfl.filters.BitmapFilter;
import animate.internal.RenderTexture;

/**
 * A FlxCamera with additional powerful features:
 * - Grab the camera screen as a `BitmapData` and use it as a texture
 * - Support `sprite.blend = DARKEN/HARDLIGHT/LIGHTEN/OVERLAY` to apply visual effects using certain sprites
 *   - NOTE: Several other blend modes work without FunkinCamera. Some still do not work.
 * - NOTE: Framerate-independent camera tweening is fixed in Flixel 6.x. Rest in peace, SwagCamera.
 */
@:nullSafety
@:access(openfl.display.DisplayObject)
@:access(openfl.display.BitmapData)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.textures.TextureBase)
@:access(flixel.graphics.FlxGraphic)
@:access(flixel.graphics.frames.FlxFrame)
class FunkinCamera extends FlxCamera
{
  public var id:String = 'unknown';

  var _blendShader:RuntimeCustomBlendShader;
  var _backgroundFrame:FlxFrame;

  var _appliedFilters:Bool = false;

  var _shouldDraw:Bool = true;

  var _blendRenderTexture:Null<RenderTexture>;
  var _backgroundRenderTexture:Null<RenderTexture>;

  var _backgroundBitmap:Null<BitmapData>;

  @:nullSafety(Off)
  public function new(id:String = 'unknown', x:Int = 0, y:Int = 0, width:Int = 0, height:Int = 0, zoom:Float = 0)
  {
    super(x, y, width, height, zoom);
    this.id = id;
    _backgroundFrame = new FlxFrame(new FlxGraphic('', null));
    _backgroundFrame.frame = new FlxRect();

    _blendShader = new RuntimeCustomBlendShader();
  }

  /**
   * Grabs the camera screen and returns it as a `BitmapData`. The returned bitmap
   * will not be referred by the camera so, changing it will not affect the scene.
   * The returned bitmap **will be reused in the next frame**, so the content is available
   * only in the current frame.
   * @param applyFilters if this is `true`, the camera's filters will be applied to the grabbed bitmap,
   * and the camera's filters will be disabled until the beginning of the next frame
   * @param isolate if this is `true`, sprites to be rendered will only be rendered to the grabbed bitmap,
   * and the grabbed bitmap will not include any previously rendered sprites
   * @param clearScreen if this is `true`, the screen will be cleared before rendering
   * @return the grabbed bitmap data
   */
  public function grabScreen(applyFilters:Bool = false, isolate:Bool = false, clearScreen:Bool = false):Null<BitmapData>
  {
    if (_backgroundBitmap == null)
    {
      var texture:Null<TextureBase> = pickTexture(width, height);
      if (texture == null) return null;

      _backgroundBitmap = FixedBitmapData.fromTexture(texture);
    }

    if (_backgroundBitmap != null)
    {
      if (applyFilters && isolate)
      {
        FlxG.log.error('cannot apply filters while isolating!');
      }
      if (_appliedFilters && applyFilters)
      {
        FlxG.log.warn('filters already applied!');
      }

      var matrix:FlxMatrix = new FlxMatrix();
      matrix.setTo(1, 0, 0, 1, flashSprite.x, flashSprite.y);

      this.render();

      if (applyFilters)
      {
        _backgroundBitmap.draw(flashSprite, matrix, true);
        @:nullSafety(Off) // TODO: Remove this once openfl.display.Sprite has been null safed.
        flashSprite.filters = null;
        _appliedFilters = true;
      }
      else
      {
        var _tmpFilters:Array<BitmapFilter> = flashSprite.filters.copy();
        @:nullSafety(Off)
        flashSprite.filters = null;
        _backgroundBitmap.draw(flashSprite, matrix, true);
        flashSprite.filters = _tmpFilters;
      }

      if (clearScreen)
      {
        // clear graphics data
        super.clearDrawStack();
        canvas.graphics.clear();
      }

      _backgroundFrame.frame.set(0, 0, width, height);
    }

    return _backgroundBitmap;
  }

  override function drawPixels(?frame:FlxFrame, ?pixels:BitmapData, matrix:FlxMatrix, ?transform:ColorTransform, ?blend:BlendMode, ?smoothing:Bool = false,
      ?shader:FlxShader):Void
  {
    if (!_shouldDraw) return;

    if ( switch blend
      {
        case DARKEN | HARDLIGHT #if !desktop | LIGHTEN #end | OVERLAY | DIFFERENCE: true;
        default: false;
      })
    {
      var background:Null<BitmapData> = grabScreen(false, false, true);
      var frameMatrix:FlxMatrix = new FlxMatrix();
      frameMatrix.copyFrom(matrix);

      @:nullSafety(Off) {
        if (_blendRenderTexture == null)
        {
          _blendRenderTexture = new RenderTexture(this.width, this.height);
        }

        _blendRenderTexture.init(this.width, this.height);
        _blendRenderTexture.drawToCamera((camera, matrix) -> {
          var pivotX:Float = width / 2;
          var pivotY:Float = height / 2;

          matrix.copyFrom(frameMatrix);
          matrix.translate(-pivotX, -pivotY);
          matrix.scale(this.zoom, this.zoom);
          matrix.translate(pivotX, pivotY);
          camera.drawPixels(frame, pixels, matrix, transform, null, smoothing, shader);
        });
        _blendRenderTexture.render();
      }
      @:nullSafety(Off)
      if (background == null || _blendRenderTexture.graphic.bitmap == null)
      {
        FlxG.log.error('Failed to get bitmap for blending!');
        super.drawPixels(frame, pixels, matrix, transform, blend, smoothing, shader);
        return;
      }

      @:nullSafety(Off)
      _blendShader.sourceSwag = _blendRenderTexture.graphic.bitmap;

      @:nullSafety(Off)
      _blendShader.backgroundSwag = background;

      _blendShader.blendSwag = blend;
      _blendShader.updateViewInfo(width, height, this);

      @:nullSafety(Off)
      _backgroundFrame.parent.bitmap = _blendRenderTexture.graphic.bitmap;

      if (_backgroundRenderTexture == null)
      {
        _backgroundRenderTexture = new RenderTexture(this.width, this.height);
      }

      _backgroundRenderTexture.init(this.width, this.height);
      _backgroundRenderTexture.drawToCamera((camera, matrix) -> {
        camera.zoom = this.zoom;
        camera.drawPixels(_backgroundFrame, null, matrix, canvas.transform.colorTransform, null, smoothing, _blendShader);
      });

      _backgroundRenderTexture.render();
      super.drawPixels(_backgroundRenderTexture.graphic.imageFrame.frame, null, new FlxMatrix(), null, null, smoothing, null);

      this.setScale(1, 1);
    }
    else
    {
      super.drawPixels(frame, pixels, matrix, transform, blend, smoothing, shader);
    }
  }

  override function destroy():Void
  {
    super.destroy();

    if (_blendRenderTexture != null)
    {
      _blendRenderTexture.destroy();
      _blendRenderTexture = null;
    }

    if (_backgroundRenderTexture != null)
    {
      _backgroundRenderTexture.destroy();
      _backgroundRenderTexture = null;
    }
  }

  override function clearDrawStack():Void
  {
    super.clearDrawStack();

    // clear filters applied flag
    _appliedFilters = false;
  }

  function pickTexture(width:Int, height:Int):Null<TextureBase>
  {
    // zero-sized textures will be problematic
    width = width < 1 ? 1 : width;
    height = height < 1 ? 1 : height;

    return Lib.current.stage.context3D.createTexture(width, height, BGRA, true);
  }
}
