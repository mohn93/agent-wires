import 'package:flutter/material.dart';

class IconRoleMap {
  static final Map<int, String> _byCodepoint = <int, String>{
    Icons.shopping_cart.codePoint: 'cart',
    Icons.shopping_bag.codePoint: 'cart',
    Icons.delete.codePoint: 'delete',
    Icons.delete_outline.codePoint: 'delete',
    Icons.arrow_back.codePoint: 'back',
    Icons.arrow_back_ios.codePoint: 'back',
    Icons.close.codePoint: 'dismiss',
    Icons.cancel.codePoint: 'dismiss',
    Icons.menu.codePoint: 'menu',
    Icons.search.codePoint: 'search',
    Icons.settings.codePoint: 'settings',
    Icons.add.codePoint: 'add',
    Icons.edit.codePoint: 'edit',
    Icons.favorite.codePoint: 'favorite',
    Icons.favorite_border.codePoint: 'favorite',
    Icons.share.codePoint: 'share',
    Icons.home.codePoint: 'home',
    Icons.person.codePoint: 'profile',
    Icons.account_circle.codePoint: 'profile',
    Icons.notifications.codePoint: 'notifications',
    Icons.more_vert.codePoint: 'more',
    Icons.more_horiz.codePoint: 'more',
    Icons.check.codePoint: 'confirm',
    Icons.check_circle.codePoint: 'confirm',
  };

  static String? roleFor(IconData icon) => _byCodepoint[icon.codePoint];
}
