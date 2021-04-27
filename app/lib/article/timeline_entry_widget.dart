import 'dart:math';
import 'dart:ui';
import "dart:ui" as ui;

import 'package:flare_flutter/flare.dart' as flare;
import 'package:flare_dart/actor_image.dart' as flare;
import 'package:flare_dart/math/aabb.dart' as flare;
import 'package:flare_dart/math/mat2d.dart' as flare;
import 'package:flare_dart/math/vec2d.dart' as flare;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:nima/nima.dart' as nima;
import 'package:nima/nima/actor_image.dart' as nima;
import 'package:nima/nima/math/aabb.dart' as nima;
import 'package:nima/nima/math/vec2d.dart' as nima;
import 'package:timeline/article/controllers/amelia_controller.dart';
import 'package:timeline/article/controllers/flare_interaction_controller.dart';
import 'package:timeline/article/controllers/newton_controller.dart';
import 'package:timeline/article/controllers/nima_interaction_controller.dart';
import 'package:timeline/timeline/timeline_entry.dart';

/// 此小部件呈现单个[TimelineEntry]。 它依赖[LeafRenderObjectWidget]，
/// 因此可以实现自定义[RenderObject]并进行相应的更新。
class TimelineEntryWidget extends LeafRenderObjectWidget {
  /// 仅在需要时才使用标志来为小部件设置动画。
  final bool isActive;
  final TimelineEntry timelineEntry;

  /// 如果此窗口小部件还具有自定义控制器，则 [interactOffset] 参数可用于检测运动效果并相应地更改 [FlareActor]。
  final Offset interactOffset;

  TimelineEntryWidget(
      {Key key, this.isActive, this.timelineEntry, this.interactOffset})
      : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _VignetteRenderObject()
      ..timelineEntry = timelineEntry
      ..isActive = isActive
      ..interactOffset = interactOffset;
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _VignetteRenderObject renderObject) {
    renderObject
      ..timelineEntry = timelineEntry
      ..isActive = isActive
      ..interactOffset = interactOffset;
  }

  @override
  didUnmountRenderObject(covariant _VignetteRenderObject renderObject) {
    renderObject
      ..isActive = false
      ..timelineEntry = null;
  }
}

/// 扩展[RenderBox]时，我们为正在渲染的小部件提供了一组自定义指令。
///
/// In particular this means overriding the [paint()] and [hitTestSelf()] methods to render the loaded
/// Flare/Nima [FlutterActor] where the widget is being placed.
class _VignetteRenderObject extends RenderBox {
  static const Alignment alignment = Alignment.center;
  static const BoxFit fit = BoxFit.contain;

  bool _isActive = false;
  bool _firstUpdate = true;
  bool _isFrameScheduled = false;
  double _lastFrameTime = 0.0;
  Offset interactOffset;
  Offset _renderOffset;

  TimelineEntry _timelineEntry;
  nima.FlutterActor _nimaActor;
  flare.FlutterActorArtboard _flareActor;
  FlareInteractionController _flareController;
  NimaInteractionController _nimaController;

  /// 每当设置新的[TimelineEntry]时调用。
  updateActor() {
    if (_timelineEntry == null) {
      /// 如果删除[_timelineEntry]，请释放其资源。
      _nimaActor?.dispose();
      _flareActor?.dispose();
      _nimaActor = null;
      _flareActor = null;
    } else {
      TimelineAsset asset = _timelineEntry.asset;
      if (asset is TimelineNima && asset.actor != null) {
        // 实例[_nimaActor]通过资产中的actor引用并为其动画设置初始起始值。
        _nimaActor = asset.actor.makeInstance();
        asset.animation.apply(asset.animation.duration, _nimaActor, 1.0);
        _nimaActor.advance(0.0);
        if (asset.filename == "assets/Newton/Newton_v2.nma") {
          //牛顿使用自定义控制器！ =）
          _nimaController = NewtonController();
          _nimaController.initialize(_nimaActor);
        }
      } else if (asset is TimelineFlare && asset.actor != null) {
        // 实例[_flareActor]通过资产中的actor引用进行设置，并为其动画设置初始起始值。
        _flareActor = asset.actor.makeInstance();
        _flareActor.initializeGraphics();
        asset.animation.apply(asset.animation.duration, _flareActor, 1.0);
        _flareActor.advance(0.0);
        if (asset.filename == "assets/Amelia_Earhart/Amelia_Earhart.flr") {
          // Amelia Earhart也使用自定义控制器。
          _flareController = AmeliaController();
          _flareController.initialize(_flareActor);
        }
      }
    }
  }

  TimelineEntry get timelineEntry => _timelineEntry;

  set timelineEntry(TimelineEntry value) {
    if (_timelineEntry == value) return;
    _timelineEntry = value;
    _firstUpdate = true;
    updateActor();
    updateRendering();
  }

  bool get isActive => _isActive;

  set isActive(bool value) {
    if (_isActive == value) return;
    _isActive = value;
    updateRendering();
  }

  /// 出于优化目的，此小部件的大小由其父级确定。
  @override
  bool get sizedByParent => true;

  /// 确定是否已轻敲此小部件。 如果是这种情况，请重新启动其动画。
  @override
  bool hitTestSelf(Offset screenOffset) {
    if (_timelineEntry != null) {
      TimelineAsset asset = _timelineEntry.asset;
      if (asset is TimelineNima && asset.actor != null) {
        asset.animationTime = 0.0;
      } else if (asset is TimelineFlare && asset.actor != null) {
        asset.animationTime = 0.0;
      }
    }
    return true;
  }

  @override
  void performResize() {
    size = constraints.biggest;
  }

  /// 这个重写的方法是我们可以实现自定义逻辑的地方，用于布置 [FlutterActor] 并将其绘制到 [canvas]。
  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final asset = _timelineEntry?.asset;
    _renderOffset = offset;

    /// 如果不需要，请不要绘画。
    if (_timelineEntry == null || asset == null) {
      return;
    }

    canvas.save();

    double w = asset.width;
    double h = asset.height;

    /// If the asset is just a static image, draw the image directly to [canvas].
    if (asset is TimelineImage) {
      canvas.drawImageRect(
          asset.image,
          Rect.fromLTWH(0.0, 0.0, w, h),
          Rect.fromLTWH(offset.dx + size.width - w, asset.y, w, h),
          Paint()
            ..isAntiAlias = true
            ..filterQuality = ui.FilterQuality.low
            ..color = Colors.white.withOpacity(asset.opacity));
    } else if (asset is TimelineNima && _nimaActor != null) {
      /// If we have a [TimelineNima] asset, set it up properly and paint it.
      ///
      /// 1. Calculate the bounds for the current object.
      /// An Axis-Aligned Bounding Box (AABB) is already set up when the asset is first loaded.
      /// We rely on this AABB to perform screen-space calculations.
      nima.AABB bounds = asset.setupAABB;

      double contentHeight = bounds[3] - bounds[1];
      double contentWidth = bounds[2] - bounds[0];
      double x =
          -bounds[0] - contentWidth / 2.0 - (alignment.x * contentWidth / 2.0);
      double y = -bounds[1] -
          contentHeight / 2.0 +
          (alignment.y * contentHeight / 2.0);

      Offset renderOffset = offset;
      Size renderSize = size;

      double scaleX = 1.0, scaleY = 1.0;

      canvas.save();

      /// This widget is always set up to use [BoxFit.contain].
      /// But this behavior can be customized according to anyone's needs.
      /// The following switch/case contains all the various alternatives native to Flutter.
      switch (fit) {
        case BoxFit.fill:
          scaleX = renderSize.width / contentWidth;
          scaleY = renderSize.height / contentHeight;
          break;
        case BoxFit.contain:
          double minScale = min(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = minScale;
          break;
        case BoxFit.cover:
          double maxScale = max(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = maxScale;
          break;
        case BoxFit.fitHeight:
          double minScale = renderSize.height / contentHeight;
          scaleX = scaleY = minScale;
          break;
        case BoxFit.fitWidth:
          double minScale = renderSize.width / contentWidth;
          scaleX = scaleY = minScale;
          break;
        case BoxFit.none:
          scaleX = scaleY = 1.0;
          break;
        case BoxFit.scaleDown:
          double minScale = min(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
          break;
      }

      /// 2. Move the [canvas] to the right position so that the widget's position
      /// is center-aligned based on its offset, size and alignment position.
      canvas.translate(
          renderOffset.dx +
              renderSize.width / 2.0 +
              (alignment.x * renderSize.width / 2.0),
          renderOffset.dy +
              renderSize.height / 2.0 +
              (alignment.y * renderSize.height / 2.0));

      /// 3. Scale depending on the [fit].
      canvas.scale(scaleX, -scaleY);

      /// 4. Move the canvas to the correct [_nimaActor] position calculated above.
      canvas.translate(x, y);

      /// 5. perform the drawing operations.
      _nimaActor.draw(canvas, 1.0);

      /// 6. Restore the canvas' original transform state.
      canvas.restore();
    } else if (asset is TimelineFlare && _flareActor != null) {
      /// If we have a [TimelineFlare] asset set it up properly and paint it.
      ///
      /// 1. Calculate the bounds for the current object.
      /// An Axis-Aligned Bounding Box (AABB) is already set up when the asset is first loaded.
      /// We rely on this AABB to perform screen-space calculations.
      flare.AABB bounds = asset.setupAABB;
      double contentWidth = bounds[2] - bounds[0];
      double contentHeight = bounds[3] - bounds[1];
      double x =
          -bounds[0] - contentWidth / 2.0 - (alignment.x * contentWidth / 2.0);
      double y = -bounds[1] -
          contentHeight / 2.0 +
          (alignment.y * contentHeight / 2.0);

      Offset renderOffset = offset;
      Size renderSize = size;

      double scaleX = 1.0, scaleY = 1.0;

      canvas.save();

      /// This widget is always set up to use [BoxFit.contain].
      /// But this behavior can be customized according to anyone's needs.
      /// The following switch/case contains all the various alternatives native to Flutter.
      switch (fit) {
        case BoxFit.fill:
          scaleX = renderSize.width / contentWidth;
          scaleY = renderSize.height / contentHeight;
          break;
        case BoxFit.contain:
          double minScale = min(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = minScale;
          break;
        case BoxFit.cover:
          double maxScale = max(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = maxScale;
          break;
        case BoxFit.fitHeight:
          double minScale = renderSize.height / contentHeight;
          scaleX = scaleY = minScale;
          break;
        case BoxFit.fitWidth:
          double minScale = renderSize.width / contentWidth;
          scaleX = scaleY = minScale;
          break;
        case BoxFit.none:
          scaleX = scaleY = 1.0;
          break;
        case BoxFit.scaleDown:
          double minScale = min(renderSize.width / contentWidth,
              renderSize.height / contentHeight);
          scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
          break;
      }

      /// 2. Move the [canvas] to the right position so that the widget's position
      /// is center-aligned based on its offset, size and alignment position.
      canvas.translate(
          renderOffset.dx +
              renderSize.width / 2.0 +
              (alignment.x * renderSize.width / 2.0),
          renderOffset.dy +
              renderSize.height / 2.0 +
              (alignment.y * renderSize.height / 2.0));

      /// 3. Scale depending on the [fit].
      canvas.scale(scaleX, scaleY);

      /// 4. Move the canvas to the correct [_flareActor] position calculated above.
      canvas.translate(x, y);

      /// 5. perform the drawing operations.
      _flareActor.draw(canvas);

      /// 6. Restore the canvas' original transform state.
      canvas.restore();
    }
    canvas.restore();
  }

  /// 使用[SchedulerBinding]触发此小部件的新绘制。
  void updateRendering() {
    if (_isActive && _timelineEntry != null) {
      markNeedsPaint();
      if (!_isFrameScheduled) {
        _isFrameScheduled = true;
        SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
      }
    }
    markNeedsLayout();
  }

  /// This callback is used by the [SchedulerBinding] in order to advance the Flare/Nima
  /// animations properly, and update the corresponding [FlutterActor]s.
  /// It is also responsible for advancing any attached components to said Actors,
  /// such as [_nimaController] or [_flareController].
  ///
  /// [SchedulerBinding]使用此回调来正确推进Flare / Nima动画，并更新相应的[FlutterActor]。
  /// 它还负责将任何附加的组件推进到所述Actor，例如[_nimaController]或[_flareController]。
  void beginFrame(Duration timeStamp) {
    _isFrameScheduled = false;
    final double t =
        timeStamp.inMicroseconds / Duration.microsecondsPerMillisecond / 1000.0;

    if (_lastFrameTime == 0) {
      _lastFrameTime = t;
      _isFrameScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
      return;
    }

    /// Calculate the elapsed time to [advance()] the animations.
    double elapsed = t - _lastFrameTime;
    _lastFrameTime = t;

    if (_timelineEntry != null) {
      TimelineAsset asset = _timelineEntry.asset;
      if (asset is TimelineNima && _nimaActor != null) {
        asset.animationTime += elapsed;

        if (asset.loop) {
          asset.animationTime %= asset.animation.duration;
        }

        /// Apply the current time to the [asset] animation.
        asset.animation.apply(asset.animationTime, _nimaActor, 1.0);
        if (_nimaController != null) {
          nima.Vec2D localTouchPosition;
          if (interactOffset != null) {
            nima.AABB bounds = asset.setupAABB;
            double contentHeight = bounds[3] - bounds[1];
            double contentWidth = bounds[2] - bounds[0];
            double x = -bounds[0] -
                contentWidth / 2.0 -
                (alignment.x * contentWidth / 2.0);
            double y = -bounds[1] -
                contentHeight / 2.0 +
                (alignment.y * contentHeight / 2.0);

            double scaleX = 1.0, scaleY = 1.0;

            switch (fit) {
              case BoxFit.fill:
                scaleX = size.width / contentWidth;
                scaleY = size.height / contentHeight;
                break;
              case BoxFit.contain:
                double minScale =
                    min(size.width / contentWidth, size.height / contentHeight);
                scaleX = scaleY = minScale;
                break;
              case BoxFit.cover:
                double maxScale =
                    max(size.width / contentWidth, size.height / contentHeight);
                scaleX = scaleY = maxScale;
                break;
              case BoxFit.fitHeight:
                double minScale = size.height / contentHeight;
                scaleX = scaleY = minScale;
                break;
              case BoxFit.fitWidth:
                double minScale = size.width / contentWidth;
                scaleX = scaleY = minScale;
                break;
              case BoxFit.none:
                scaleX = scaleY = 1.0;
                break;
              case BoxFit.scaleDown:
                double minScale =
                    min(size.width / contentWidth, size.height / contentHeight);
                scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
                break;
            }
            double dx = interactOffset.dx -
                (_renderOffset.dx +
                    size.width / 2.0 +
                    (alignment.x * size.width / 2.0));
            double dy = interactOffset.dy -
                (_renderOffset.dy +
                    size.height / 2.0 +
                    (alignment.y * size.height / 2.0));
            dx /= scaleX;
            dy /= -scaleY;
            dx -= x;
            dy -= y;

            /// Use this logic to evaluate the correct touch position that will
            /// be passed down to [NimaInteractionController.advance()].
            localTouchPosition = nima.Vec2D.fromValues(dx, dy);
          }

          /// This custom [NimaInteractionController] uses [localTouchPosition] to perform its calculations.
          _nimaController.advance(_nimaActor, localTouchPosition, elapsed);
        }
        _nimaActor.advance(elapsed);
      } else if (asset is TimelineFlare && _flareActor != null) {
        /// Some [TimelineFlare] assets have a custom intro that's played
        /// when they're painted for the first time.
        if (_firstUpdate) {
          if (asset.intro != null) {
            asset.animation = asset.intro;
            asset.animationTime = -1.0;
          }
          _firstUpdate = false;
        }
        asset.animationTime += elapsed;
        if (asset.idleAnimations != null) {
          /// If an [idleAnimation] is set up, the current time is calculated and applied to it.
          double phase = 0.0;
          for (flare.ActorAnimation animation in asset.idleAnimations) {
            animation.apply((asset.animationTime + phase) % animation.duration,
                _flareActor, 1.0);
            phase += 0.16;
          }
        } else {
          if (asset.intro == asset.animation &&
              asset.animationTime >= asset.animation.duration) {
            asset.animationTime -= asset.animation.duration;
            asset.animation = asset.idle;
          }
          if (asset.loop && asset.animationTime >= 0) {
            asset.animationTime %= asset.animation.duration;
          }

          /// Apply the current time to this [ActorAnimation].
          asset.animation.apply(asset.animationTime, _flareActor, 1.0);
        }
        if (_flareController != null) {
          flare.Vec2D localTouchPosition;
          if (interactOffset != null) {
            flare.AABB bounds = asset.setupAABB;
            double contentWidth = bounds[2] - bounds[0];
            double contentHeight = bounds[3] - bounds[1];
            double x = -bounds[0] -
                contentWidth / 2.0 -
                (alignment.x * contentWidth / 2.0);
            double y = -bounds[1] -
                contentHeight / 2.0 +
                (alignment.y * contentHeight / 2.0);

            double scaleX = 1.0, scaleY = 1.0;

            switch (fit) {
              case BoxFit.fill:
                scaleX = size.width / contentWidth;
                scaleY = size.height / contentHeight;
                break;
              case BoxFit.contain:
                double minScale =
                    min(size.width / contentWidth, size.height / contentHeight);
                scaleX = scaleY = minScale;
                break;
              case BoxFit.cover:
                double maxScale =
                    max(size.width / contentWidth, size.height / contentHeight);
                scaleX = scaleY = maxScale;
                break;
              case BoxFit.fitHeight:
                double minScale = size.height / contentHeight;
                scaleX = scaleY = minScale;
                break;
              case BoxFit.fitWidth:
                double minScale = size.width / contentWidth;
                scaleX = scaleY = minScale;
                break;
              case BoxFit.none:
                scaleX = scaleY = 1.0;
                break;
              case BoxFit.scaleDown:
                double minScale =
                    min(size.width / contentWidth, size.height / contentHeight);
                scaleX = scaleY = minScale < 1.0 ? minScale : 1.0;
                break;
            }
            double dx = interactOffset.dx -
                (_renderOffset.dx +
                    size.width / 2.0 +
                    (alignment.x * size.width / 2.0));
            double dy = interactOffset.dy -
                (_renderOffset.dy +
                    size.height / 2.0 +
                    (alignment.y * size.height / 2.0));
            dx /= scaleX;
            dy /= scaleY;
            dx -= x;
            dy -= y;

            /// Use this logic to evaluate the correct touch position that will
            /// be passed down to [FlareInteractionController.advance()].
            localTouchPosition = flare.Vec2D.fromValues(dx, dy);
          }

          /// Perform the actual [advance()]ing.
          _flareController.advance(_flareActor, localTouchPosition, elapsed);
        }

        /// Advance the [FlutterActorArtboard].
        _flareActor.advance(elapsed);
      }
    }

    /// Invalidate the current widget visual state and let Flutter paint it again.
    markNeedsPaint();

    /// Schedule a new frame to update again - but only if needed.
    if (isActive && !_isFrameScheduled) {
      _isFrameScheduled = true;
      SchedulerBinding.instance.scheduleFrameCallback(beginFrame);
    }
  }
}
