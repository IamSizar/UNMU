import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../localization/app_localizations.dart';
import '../../services/api_service.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../screens/stock_detail/stock_detail_screen.dart';
import '../../utils/haptic_utils.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotifications();
    });
  }

  Future<void> _loadNotifications() async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final notifications = await ApiService.getNotifications(authProvider.token!);
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(context);
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    
    if (!authProvider.isAuthenticated) {
      return Scaffold(
        appBar: PlatformAppBar(title: l10n.notifications),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.notifications_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                l10n.pleaseLoginToViewNotifications,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: PlatformAppBar(
        title: l10n.notifications,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noNotifications,
                        style: theme.textTheme.headlineMedium,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      final isRead = notification['is_read'] == true;
                      final type = notification['type']?.toString() ?? '';
                      
                      Color notificationColor;
                      IconData icon;
                      if (type.contains('STATUS')) {
                        notificationColor = HalalFintechTheme.mixedYellow;
                        icon = Icons.swap_horiz;
                      } else if (type.contains('PURIFICATION')) {
                        notificationColor = HalalFintechTheme.accentGreen;
                        icon = Icons.trending_up;
                      } else {
                        notificationColor = HalalFintechTheme.accentGreen;
                        icon = Icons.info;
                      }
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: isRead ? null : notificationColor.withValues(alpha: 0.05),
                        child: InkWell(
                          onTap: () async {
                            await HapticUtils.lightTap();
                            if (!mounted) return;
                            // Navigate to stock detail if notification has stock info
                            final ticker = notification['ticker']?.toString();
                            final exchange = notification['exchange']?.toString();
                            
                            if (ticker != null && exchange != null && ticker.isNotEmpty && exchange.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StockDetailScreen(
                                    ticker: ticker,
                                    exchange: exchange,
                                  ),
                                ),
                              );
                            }
                          },
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: notificationColor.withValues(alpha: 0.1),
                              child: Icon(icon, color: notificationColor),
                            ),
                            title: Text(
                              notification['title']?.toString() ?? '',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  notification['message']?.toString() ?? '',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (notification['created_at'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(notification['created_at'], l10n.isArabic),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: (theme.textTheme.bodySmall?.color ?? Colors.grey).withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: isRead
                                ? null
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: notificationColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _formatDate(dynamic date, bool isArabic) {
    if (date == null) return '';
    
    try {
      DateTime dateTime;
      if (date is String) {
        dateTime = DateTime.parse(date);
      } else if (date is DateTime) {
        dateTime = date;
      } else {
        return '';
      }
      
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return isArabic ? 'الآن' : 'Just now';
          }
          return isArabic 
              ? 'منذ ${difference.inMinutes} دقيقة'
              : '${difference.inMinutes}m ago';
        }
        return isArabic 
            ? 'منذ ${difference.inHours} ساعة'
            : '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return isArabic 
            ? 'منذ ${difference.inDays} يوم'
            : '${difference.inDays}d ago';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return '';
    }
  }
}

