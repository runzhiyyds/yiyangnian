import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// 统一加载占位组件，减少布局跳动
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({
    super.key,
    this.child,
    this.useShimmer = true,
  });

  /// 自定义子组件；为 null 时使用默认的列表骨架
  final Widget? child;

  /// 是否使用 Shimmer 动画
  final bool useShimmer;

  @override
  Widget build(BuildContext context) {
    final content = child ?? _buildDefaultSkeleton(context);
    if (useShimmer) {
      return Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: content,
      );
    }
    return content;
  }

  Widget _buildDefaultSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(height: 24, width: 120),
          const SizedBox(height: 16),
          _shimmerBox(height: 16, width: double.infinity),
          const SizedBox(height: 8),
          _shimmerBox(height: 16, width: 200),
          const SizedBox(height: 8),
          _shimmerBox(height: 16, width: 160),
          const SizedBox(height: 24),
          _shimmerBox(height: 48, width: double.infinity),
          const SizedBox(height: 12),
          _shimmerBox(height: 48, width: double.infinity),
          const SizedBox(height: 24),
          _shimmerBox(height: 16, width: 100),
          const SizedBox(height: 8),
          ...List.generate(5, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _shimmerBox(height: 56, width: double.infinity),
          )),
        ],
      ),
    );
  }

  Widget _shimmerBox({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// 全屏加载占位（用于列表页、详情页初次加载），使用骨架减少布局跳动
class FullPageLoadingPlaceholder extends StatelessWidget {
  const FullPageLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: LoadingPlaceholder(),
    );
  }
}
