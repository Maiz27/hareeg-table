import 'cpu_move_plan.dart';
import 'priority_cpu_move_planner.dart';

export 'cpu_move_plan.dart';
export 'expert_cpu_move_planner.dart';
export 'priority_cpu_move_planner.dart';
export 'skilled_cpu_move_planner.dart';

/// Compatibility facade for the original Classic Hareeg CPU move planner API.
abstract final class ClassicHareegCpuMovePlanner {
  /// Deprecated: use [PriorityCpuMovePlanner] through [CpuMovePlanner].
  static ClassicHareegCpuMovePlan evaluate(Iterable<String> legalActionIds) {
    return PriorityCpuMovePlanner.evaluate(legalActionIds);
  }
}
