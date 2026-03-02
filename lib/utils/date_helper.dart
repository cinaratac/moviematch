import 'package:intl/intl.dart';

class DateHelper {
  /// Şu anki haftayı benzersiz bir ID olarak döndürür. Örn: "2024_15"
  static String getCurrentWeekId() {
    return getWeekIdFor(DateTime.now());
  }

  /// İstenilen tarihin hafta ID'sini verir.
  static String getWeekIdFor(DateTime date) {
    // intl paketi ile yılın kaçıncı günü olduğunu buluyoruz (Day of Year)
    final dayOfYear = int.parse(DateFormat("D").format(date));
    // Basit hafta hesaplaması
    final weekNum = ((dayOfYear - date.weekday + 10) / 7).floor();
    return "${date.year}_$weekNum";
  }
}