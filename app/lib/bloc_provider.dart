import "package:flutter/widgets.dart";
import "package:timeline/blocs/favorites_bloc.dart";
import 'package:timeline/search_manager.dart';
import 'package:timeline/timeline/timeline.dart';
import 'package:timeline/timeline/timeline_entry.dart';

/// This [InheritedWidget] wraps the whole app, and provides access
/// to the user's favorites through the [FavoritesBloc]
/// and the [Timeline] object.
class BlocProvider extends InheritedWidget {
  final FavoritesBloc favoritesBloc;
  final Timeline timeline;

  /// This widget is initialized when the app boots up, and thus loads the resources.
  /// The timeline.json file contains all the entries' data.
  /// Once those entries have been loaded, load also all the favorites.
  /// Lastly use the entries' references to load a local dictionary for the [SearchManager].
  BlocProvider(
      {Key key,
      FavoritesBloc fb,
      Timeline t,
      @required Widget child,
      TargetPlatform platform = TargetPlatform.iOS})
      : timeline = t ?? Timeline(platform),
        favoritesBloc = fb ?? FavoritesBloc(),
        super(key: key, child: child) {
    timeline.loadFromBundle("assets/timeline.json").then((entries) {
      // timeline.setViewport(
      //     start: entries.first.start * 2.0,
      //     end: entries.first.start,
      //     animate: true);

      /// 将时间轴推进到起始位置.
      // timeline.advance(0.0, false);

      // print(
      //     '------------------------------------------TIME LINE INFO-----------------------------------------------------');
      // print('timeline.renderStart: ${timeline.renderStart}');
      // print('timeline.start: ${timeline.start}');
      // print('timeline.renderEnd: ${timeline.renderEnd}');
      // print('timeline.end: ${timeline.end}');
      // print(
      //     '------------------------------------------TIME LINE INFO-----------------------------------------------------');

      /// All the entries are loaded, we can fill in the [favoritesBloc]...
      favoritesBloc.init(entries);

      /// ...and initialize the [SearchManager].
      SearchManager.init(entries);
    });
  }

  @override
  updateShouldNotify(InheritedWidget oldWidget) => true;

  /// static accessor for the [FavoritesBloc].
  /// e.g. [ArticleWidget] retrieves the favorites information using this static getter.
  static FavoritesBloc favorites(BuildContext context) {
    BlocProvider bp =
        context.dependOnInheritedWidgetOfExactType<BlocProvider>();
    FavoritesBloc bloc = bp?.favoritesBloc;
    return bloc;
  }

  /// static accessor for the [Timeline].
  /// e.g. [_MainMenuWidgetState.navigateToTimeline] uses this static getter to access build the [TimelineWidget].
  static Timeline getTimeline(BuildContext context) {
    BlocProvider bp =
        context.dependOnInheritedWidgetOfExactType<BlocProvider>();
    Timeline bloc = bp?.timeline;
    return bloc;
  }
}
