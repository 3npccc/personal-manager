import 'package:flutter/material.dart';

/// 一个导航目的地（左侧导航栏的一项）
class NavDestination {
  const NavDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// 稳定标识，用于持久化"上次停留的页面"
  final String id;

  /// 中文显示名
  final String label;

  /// 未选中图标
  final IconData icon;

  /// 选中图标
  final IconData selectedIcon;
}

/// 第一版全部 9 个导航目的地（顺序即显示顺序）
const List<NavDestination> kNavDestinations = <NavDestination>[
  NavDestination(
    id: 'home',
    label: '概览',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  NavDestination(
    id: 'todos',
    label: '待办',
    icon: Icons.check_circle_outline,
    selectedIcon: Icons.check_circle,
  ),
  NavDestination(
    id: 'notes',
    label: '笔记',
    icon: Icons.sticky_note_2_outlined,
    selectedIcon: Icons.sticky_note_2,
  ),
  NavDestination(
    id: 'ledger',
    label: '记账',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
  ),
  NavDestination(
    id: 'study',
    label: '学习',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
  ),
  NavDestination(
    id: 'work',
    label: '工作',
    icon: Icons.work_outline,
    selectedIcon: Icons.work,
  ),
  NavDestination(
    id: 'life',
    label: '生活',
    icon: Icons.favorite_outline,
    selectedIcon: Icons.favorite,
  ),
  NavDestination(
    id: 'backup',
    label: '备份恢复',
    icon: Icons.backup_outlined,
    selectedIcon: Icons.backup,
  ),
  NavDestination(
    id: 'settings',
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];
