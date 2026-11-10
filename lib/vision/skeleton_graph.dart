import 'dart:math' as math;
import 'dart:typed_data';

/// A 2-D point in working-image pixels.
class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;

  double dist(Pt o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// A piece of skeleton between two nodes (ends or junctions).
class Segment {
  Segment(this.id, this.pts);
  final int id;
  final List<Pt> pts;

  double get length {
    var s = 0.0;
    for (var i = 1; i < pts.length; i++) {
      s += pts[i].dist(pts[i - 1]);
    }
    return s;
  }
}

/// Segments joined end to end into one continuous crease.
class Curve {
  Curve(this.pts, this.segmentIds, this.gaps);

  final List<Pt> pts;
  final List<int> segmentIds;

  /// Gaps bridged while joining (each one a visible break in the line):
  /// index in [pts] where the gap ends, and its length in pixels.
  final List<({int at, double length})> gaps;

  double get length {
    var s = 0.0;
    for (var i = 1; i < pts.length; i++) {
      s += pts[i].dist(pts[i - 1]);
    }
    return s;
  }
}

/// Turns a one-pixel skeleton into segments, then joins segments that
/// continue each other smoothly into curves.
class SkeletonGraph {
  SkeletonGraph(this.skeleton, this.width, this.height) {
    _trace();
  }

  final Uint8List skeleton;
  final int width;
  final int height;
  final List<Segment> segments = [];

  /// Junction pixels (three or more neighbors).
  final List<Pt> junctions = [];

  int _deg(int i) {
    final x = i % width, y = i ~/ width;
    var n = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
        if (skeleton[ny * width + nx] != 0) n++;
      }
    }
    return n;
  }

  Iterable<int> _neighbors(int i) sync* {
    final x = i % width, y = i ~/ width;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
        final q = ny * width + nx;
        if (skeleton[q] != 0) yield q;
      }
    }
  }

  Pt _pt(int i) => Pt((i % width).toDouble(), (i ~/ width).toDouble());

  void _trace() {
    final n = skeleton.length;
    final deg = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (skeleton[i] != 0) deg[i] = _deg(i);
    }
    bool isNode(int i) => deg[i] != 2;
    final visited = Uint8List(n);

    List<int> walk(int start, int first) {
      final path = <int>[start, first];
      visited[first] = 1;
      var prev = start, cur = first;
      while (true) {
        int? next;
        for (final q in _neighbors(cur)) {
          if (q == prev || q == start && path.length < 3) continue;
          if (isNode(q)) {
            next = q;
            break;
          }
          if (visited[q] == 0) next ??= q;
        }
        if (next == null) break;
        path.add(next);
        if (isNode(next)) break;
        visited[next] = 1;
        prev = cur;
        cur = next;
      }
      return path;
    }

    for (var i = 0; i < n; i++) {
      if (skeleton[i] == 0 || !isNode(i)) continue;
      if (deg[i] >= 3) junctions.add(_pt(i));
      for (final q in _neighbors(i)) {
        if (isNode(q) || visited[q] != 0) continue;
        final path = walk(i, q);
        if (path.length >= 3) {
          segments.add(Segment(segments.length, [for (final p in path) _pt(p)]));
        }
      }
    }
    // Closed loops have no nodes.
    for (var i = 0; i < n; i++) {
      if (skeleton[i] == 0 || isNode(i) || visited[i] != 0) continue;
      visited[i] = 1;
      final nb = _neighbors(i).where((q) => !isNode(q)).toList();
      if (nb.isEmpty) continue;
      final path = walk(i, nb.first);
      if (path.length >= 3) {
        segments.add(Segment(segments.length, [for (final p in path) _pt(p)]));
      }
    }
  }

  /// Joins segments into curves.
  ///
  /// Two segment ends are joined when they are close and the line runs on
  /// smoothly (small turn). Gaps up to [maxGap] pixels are bridged and
  /// recorded as breaks. Each end joins at most once.
  List<Curve> link({required double maxGap, double maxTurnDeg = 40}) {
    final ends = <_End>[];
    for (final s in segments) {
      if (s.pts.length < 2) continue;
      ends.add(_End(s, true));
      ends.add(_End(s, false));
    }
    final cands = <(double, int, int)>[];
    final maxTurn = maxTurnDeg * math.pi / 180;
    for (var a = 0; a < ends.length; a++) {
      for (var b = a + 1; b < ends.length; b++) {
        final ea = ends[a], eb = ends[b];
        if (ea.seg.id == eb.seg.id) continue;
        final d = ea.pos.dist(eb.pos);
        if (d > maxGap) continue;
        // eb must continue ea: eb's outward direction is opposite to ea's.
        final turn = _angle(ea.dx, ea.dy, -eb.dx, -eb.dy);
        if (turn > maxTurn) continue;
        if (d > 3) {
          final vx = eb.pos.x - ea.pos.x, vy = eb.pos.y - ea.pos.y;
          if (_angle(ea.dx, ea.dy, vx, vy) > maxTurn * 0.9) continue;
          if (_angle(-eb.dx, -eb.dy, vx, vy) > maxTurn * 0.9) continue;
        }
        final cost = turn * 180 / math.pi + d * 1.5 - math.min(ea.seg.length, eb.seg.length) * 0.05;
        cands.add((cost, a, b));
      }
    }
    cands.sort((x, y) => x.$1.compareTo(y.$1));

    final partner = List<int>.filled(ends.length, -1);
    final parent = List<int>.generate(segments.length, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (final (_, a, b) in cands) {
      if (partner[a] != -1 || partner[b] != -1) continue;
      final ra = find(ends[a].seg.id), rb = find(ends[b].seg.id);
      if (ra == rb) continue; // would close a loop
      partner[a] = b;
      partner[b] = a;
      parent[ra] = rb;
    }

    // Index of each segment's ends in [ends].
    final endIndex = <int, (int, int)>{};
    for (var i = 0; i < ends.length; i += 2) {
      endIndex[ends[i].seg.id] = (i, i + 1);
    }

    final used = <int>{};
    final curves = <Curve>[];
    for (final s in segments) {
      if (used.contains(s.id) || !endIndex.containsKey(s.id)) continue;
      // Walk to one extreme of the chain first.
      var segId = s.id;
      var exitIsStart = true; // leave through the start end
      final guard = <int>{};
      while (true) {
        final (si, ei) = endIndex[segId]!;
        final exitEnd = exitIsStart ? si : ei;
        final p = partner[exitEnd];
        if (p == -1 || guard.contains(segId)) break;
        guard.add(segId);
        final nextSeg = ends[p].seg.id;
        // We arrive at end p; continue out of the other end.
        exitIsStart = !ends[p].isStart;
        segId = nextSeg;
      }
      // Now traverse forward from that extreme. We are at segId and the
      // chain's free end is the one we would "exit" through; so we enter
      // forward from it.
      var entryIsStart = exitIsStart;
      final pts = <Pt>[];
      final ids = <int>[];
      final gaps = <({int at, double length})>[];
      while (true) {
        if (used.contains(segId)) break;
        used.add(segId);
        ids.add(segId);
        final seg = segments[segId];
        final ordered = entryIsStart ? seg.pts : seg.pts.reversed.toList();
        if (pts.isNotEmpty) {
          final d = pts.last.dist(ordered.first);
          if (d > 3) gaps.add((at: pts.length, length: d));
        }
        pts.addAll(ordered);
        final (si, ei) = endIndex[segId]!;
        final exitEnd = entryIsStart ? ei : si;
        final p = partner[exitEnd];
        if (p == -1) break;
        segId = ends[p].seg.id;
        entryIsStart = ends[p].isStart;
      }
      curves.add(Curve(pts, ids, gaps));
    }
    return curves;
  }

  static double _angle(double ax, double ay, double bx, double by) {
    final la = math.sqrt(ax * ax + ay * ay), lb = math.sqrt(bx * bx + by * by);
    if (la == 0 || lb == 0) return math.pi;
    final c = ((ax * bx + ay * by) / (la * lb)).clamp(-1.0, 1.0);
    return math.acos(c);
  }
}

/// One end of a segment, with its outward direction.
class _End {
  _End(this.seg, this.isStart) {
    final p = seg.pts;
    final k = math.min(6, p.length - 1);
    final end = isStart ? p.first : p.last;
    final inner = isStart ? p[k] : p[p.length - 1 - k];
    pos = end;
    dx = end.x - inner.x;
    dy = end.y - inner.y;
  }

  final Segment seg;
  final bool isStart;
  late final Pt pos;
  late final double dx;
  late final double dy;
}
