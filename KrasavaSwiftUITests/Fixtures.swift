@testable import KrasavaSwiftUI
import Foundation

/// Фикстуры фида — срез настоящего ответа `schedule-of.mirea.ru`.
///
/// Держим их строкой в Swift-файле, а не ресурсом в бандле: тест не должен
/// зависеть от того, попал ли файл в копию ресурсов тестового таргета.
/// Содержимое при этом остаётся читаемым — это построчный срез реального фида
/// с сохранёнными переносами строк, экранированием и порядком свойств.
enum Fixtures {

    /// Срез фида группы ИКБО-10-25 (осень 2026).
    ///
    /// Специально содержит всё, что ломало парсеры:
    ///  * перенос длинных строк с ведущим пробелом;
    ///  * маркеры недель «N неделя» с `TRANSP:TRANSPARENT`;
    ///  * `RRULE` с `INTERVAL=2` и `UNTIL`;
    ///  * `EXDATE` с несколькими датами и временем;
    ///  * занятие без `X-META-DISCIPLINE` (только `SUMMARY`);
    ///  * дистанционную пару с аудиторией «СДО»;
    ///  * полное название типа вместо аббревиатуры.
    static let feedSample = #"""
BEGIN:VCALENDAR
PRODID:-//github.com/ical-org/ical.net//NONSGML ical.net//EN
VERSION:2.0
X-WR-CALNAME:ИКБО-10-25
BEGIN:VTIMEZONE
TZID:Europe/Moscow
BEGIN:STANDARD
DTSTART:20000101T000000
TZOFFSETFROM:+0300
TZOFFSETTO:+0300
END:STANDARD
END:VTIMEZONE
BEGIN:X-SCHEDULE-VERSION
SVID:4772
X-SV-END:2026-12-30T21:00:00.0000000Z
X-SV-START:2026-08-31T21:00:00.0000000Z
X-SV-TYPE:SEMESTER
END:X-SCHEDULE-VERSION
BEGIN:VEVENT
DTEND;VALUE=DATE:20260908
DTSTART;VALUE=DATE:20260901
SEQUENCE:0
SUMMARY:1 неделя
TRANSP:TRANSPARENT
UID:week-1
END:VEVENT
BEGIN:VEVENT
DTEND;VALUE=DATE:20260915
DTSTART;VALUE=DATE:20260907
SEQUENCE:0
SUMMARY:2 неделя
TRANSP:TRANSPARENT
UID:week-2
END:VEVENT
BEGIN:VEVENT
DTEND;VALUE=DATE:20260922
DTSTART;VALUE=DATE:20260914
SEQUENCE:0
SUMMARY:3 неделя
TRANSP:TRANSPARENT
UID:week-3
END:VEVENT
BEGIN:VEVENT
CATEGORIES:ЛК
DTEND;TZID=Europe/Moscow:20260914T103000
DTSTART;TZID=Europe/Moscow:20260914T090000
EXDATE;TZID=Europe/Moscow:20260831T090000,20261221T090000
LOCATION:А-10 (В-78)
RRULE:FREQ=WEEKLY;INTERVAL=2;UNTIL=20261230T210000Z
SEQUENCE:0
SUMMARY:ЛК Конфигурационное управление
TRANSP:OPAQUE
UID:9a2cf326-561b-5f08-92cc-f96b03723afa
X-META-AUDITORIUM;VALUE=TEXT;ID=320;TYPE=3;NUMBER=А-10;CAMPUS=В-78:А-10 
 (В-78)
X-META-DISCIPLINE;VALUE=TEXT:Конфигурационное управл
 ение
X-META-FULL_LESSON_TYPE;VALUE=TEXT:Лекции
X-META-GROUP;VALUE=TEXT;ID=5539;TYPE=1:ИКБО-10-25
X-META-LESSON_TYPE;VALUE=TEXT:ЛК
X-META-TEACHER;VALUE=TEXT;ID=959;TYPE=2:Мирзоян Дмитрий Ил
 ьич
END:VEVENT
BEGIN:VEVENT
CATEGORIES:ПР
DTEND;TZID=Europe/Moscow:20260915T121000
DTSTART;TZID=Europe/Moscow:20260915T104000
RRULE:FREQ=WEEKLY;INTERVAL=1;UNTIL=20261230T210000Z
SEQUENCE:0
SUMMARY:ПР Аналитическая практика
TRANSP:OPAQUE
UID:practice-uid
X-META-AUDITORIUM;VALUE=TEXT;ID=837;TYPE=3;NUMBER:С-20
X-META-DISCIPLINE;VALUE=TEXT:Аналитическая практика
X-META-FULL_LESSON_TYPE;VALUE=TEXT:Практические занятия
X-META-GROUP;VALUE=TEXT;ID=5539;TYPE=1:ИКБО-10-25
X-META-LESSON_TYPE;VALUE=TEXT:ПР
X-META-TEACHER;VALUE=TEXT;ID=640;TYPE=2:Алпатов Алексей Николаевич
END:VEVENT
BEGIN:VEVENT
CATEGORIES:СР
DTEND;TZID=Europe/Moscow:20260916T103000
DTSTART;TZID=Europe/Moscow:20260916T090000
SEQUENCE:0
SUMMARY:СР Аналитическая практика
TRANSP:OPAQUE
UID:remote-uid
X-META-AUDITORIUM;VALUE=TEXT;ID=900;TYPE=3;NUMBER:СДО
X-META-DISCIPLINE;VALUE=TEXT:Аналитическая практика
X-META-FULL_LESSON_TYPE;VALUE=TEXT:Самостоятельная работа
X-META-GROUP;VALUE=TEXT;ID=5539;TYPE=1:ИКБО-10-25
X-META-LESSON_TYPE;VALUE=TEXT:СР
END:VEVENT
END:VCALENDAR
"""#

    /// Тот же фид, но с другими `UID` у занятий.
    ///
    /// Нужен для регресс-теста на потерю заметок: вуз пересобирает iCal, `UID`
    /// меняются, а заметка пользователя должна остаться на месте.
    static let feedSampleWithRotatedUIDs = feedSample
        .replacingOccurrences(of: "9a2cf326-561b-5f08-92cc-f96b03723afa", with: "rotated-lecture")
        .replacingOccurrences(of: "practice-uid", with: "rotated-practice")
        .replacingOccurrences(of: "remote-uid", with: "rotated-remote")

    /// Мусорный ответ сервера в техобслуживании.
    static let htmlInsteadOfICal = #"""
<!DOCTYPE html>
<html><head><title>502 Bad Gateway</title></head>
<body><h1>503 Service Unavailable</h1></body></html>
"""#
}