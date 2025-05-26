#!/usr/bin/perl -wT

use warnings;
use strict;
use CGI;
use DBI;
use POSIX;

# Размер страницы (кол-во строк) при постраничном показе
my($PAGE_SIZE) = 150;
# Кол-во кнопок страницы в окошке пейджера
my($WINDOW_SIZE) = 8;
# Имя самого скрипта
my($self_name) = 'logs.pl';


# Строковые названия SYSLOG констант источника
my(@factility) = ('kern', 'user', 'mail', 'daemon', 'auth', 'syslog', 'lpr', 'news', 'uucp', 'clock', 'authpriv',
                  'ftp', 'ntp', 'log audit', 'log alert', 'cron', 'local0', 'local1', 'local2', 'local3', 'local4',
                  'local5', 'local6', 'local7');

# Строковые названия и цвета фона/шрифта для уровней важности
my(@severity)  = ('Emergency', 'Alert',     'Critical',  'Error',  'Warning', 'Notice',    'Informational', 'Debug');
my(@bgcolor)   = ('Red',       'VioletRed', 'OrangeRed', 'Purple', 'Gold',    'PaleGreen', 'Aquamarine',    'PowderBlue');
my(@fontcolor) = ('White',     'Black',     'White',     'White',  'Black',   'Black',     'Black',         'Black');

# Образец описателя пейджера:
#    first_page - Код кнопки перехода на первую страницу %u% - URL перехода
#    prev_page  - Код кнопки перехода на предыдущую страницу %u% - URL перехода
#    next_page  - Код кнопки перехода на следующую страницу %u% - URL перехода
#    last_page  - Код кнопки перехода на последнюю страницу %u% - URL перехода
#    curr_page  - Код кнопки текущей страницы
#    page       - Код кнопки перехода на страницу с номером %n%, %u% - URL перехода
#    begin      - Код начала пейджера
#    end        - Код конца пейджера
#    no_pager   - Код, возвращаемый, если пейджер вообще не нужен.
#    all        - Код кнопки "Все списком"
#    pager      - Код кнопки "Постранично"
my(%pager) = ('first_page' => '<TD><A href="%u%" title="В начало">&lt;&lt;</A></TD>',
              'prev_page'  => '<TD><A href="%u%" title=\'-1\'>&lt;</A></TD>',
              'next_page'  => '<TD><A href="%u%" title=\'+1\'>&gt;</A></TD>',
              'last_page'  => '<TD><A href="%u%" title=\'В конец\'>&gt;&gt;</A></TD>',
              'curr_page'  => '<TD><FONT color=\'black\'>%n%</font></TD>',
              'page'       => '<TD><A href="%u%">%n%</A></TD>',
              'begin'      => '<TABLE>',
              'end'        => '</TABLE>',
              'no_pager'   => '&nbsp;',
              'all'        => '<A href="%u%">Весь список</A>',
              'pager'      => '<A href="%u%">Постранично</A>'
             );



# имя базы данных
my($dbname) = 'logs';
# имя пользователя
my($username) = 'loguser';
# пароль
my($password) = 'password';
# имя или IP адрес сервера
my($dbhost) = 'localhost';
# порт
my($dbport) = '';

print "Content-Type: text/html\n\n";
print "<HTML>\n";
print "  <HEAD>\n";
print "  </HEAD>\n";
print "  <BODY>\n";



my($dbh) = DBI->connect("dbi:MariaDB:dbname=$dbname;host=$dbhost","$username","$password", {PrintError => 1});
my($sth, $page, $pg, $dip, $ip, $dev, $device, $cmd);

$dip = CGI::param('ip');
$dip =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
$ip = $1;


if (defined($ip)) {
  $sth = $dbh->prepare("SELECT id FROM devices WHERE ip = inet_aton(?)");
  $sth->execute($ip);
  ($device) = $sth->fetchrow_array();
  if ($device) {
    $cmd = 'show';
    $page = 1;
  } else {
    $cmd = 'notfound';
  }
} else {
  $dev = CGI::param('device');
  $dev =~ /(\d+)/;
  $device = $1;

  $cmd = CGI::param('cmd');
  unless (defined($cmd)) {
    $cmd = 'none';
  }

  $pg = CGI::param('page');
  $pg =~ /(\d+)/;
  $page = $1;
}


$sth = $dbh->prepare("SELECT id, name FROM devices ORDER BY ip, name");
$sth->execute();

# Печать формы выбора устройства
print "    <FORM>\n";
print "      Устройство:\n";

print "      <SELECT name='device'>\n";
my($id, $name);
while (($id, $name) = $sth->fetchrow_array()) {
  if (defined($device) && $id == $device) {
    print "        <OPTION value='$id' SELECTED>$name</OPTION>\n";
  } else {
    print "        <OPTION value='$id'>$name</OPTION>\n";
  }
}
$sth->finish();


print "      </SELECT>\n";
print "      <INPUT type='submit' value='Посмотреть'>\n";
print "      <INPUT type='hidden' value='show' name='cmd'>\n";
print "      <INPUT type='hidden' value='1' name='page'>\n";
print "      <INPUT type='button' value='Изменить' OnClick=\"window.location='logs.pl?cmd=edit&device=' + document.getElementsByName('device')[0].value\">\n";
print "    </FORM>\n";

if ($cmd eq 'show' && defined($device)) {

  # Выводим логи заказанного устройства
  $sth = $dbh->prepare("SELECT model, comment FROM devices WHERE id = ?");
  $sth->execute($device);
  my($model, $comment) = $sth->fetchrow_array();
  $sth->finish();

  $sth = $dbh->prepare("SELECT count(*) FROM logs WHERE device = ?");
  $sth->execute($device);
  my($count) = $sth->fetchrow_array();
  $sth->finish();

  print "    <H4>Модель: $model, $count записей</H4>\n";
  if ($comment) {
    print "    <PRE>$comment</PRE>\n";
  }

  # Нужно ли листать страницы?
  if ($count > $PAGE_SIZE) {
    print pager_html(\%pager, $count);
    print pager_onoff(\%pager);
  }

  # Собственно таблица с логами, постранично или нет.
  print "    <TABLE border=1>\n";
  print "      <TR bgcolor='blue'>\n";
  print "        <TD><FONT color='white'>№</TD>\n";
  print "        <TD><FONT color='white'>Дата</TD>\n";
  print "        <TD><FONT color='white'>Хост</TD>\n";
  print "        <TD><FONT color='white'>Тэг</TD>\n";
  print "        <TD><FONT color='white'>Источник</TD>\n";
  print "        <TD><FONT color='white'>Важность</TD>\n";
  print "        <TD><FONT color='white'>Сообщение</TD>\n";
  print "      </TR>\n";

#  print "SELECT date, logstring, facility, severity, tag, hname FROM logs WHERE device=? ORDER BY id DESC" . pager_sql() . "\n";

  $sth = $dbh->prepare("SELECT date, logstring, facility, severity, tag, hname FROM logs WHERE device=? ORDER BY id DESC" . pager_sql() );
  $sth->execute($device);

  # Номер строки
  my($n);
  if ($page == 0) {
    # Если пейджера нет - то сквозная нумерация
    $n = 1;
  } else {
    # Если пейджер есть - то вычисляем из нометра страницы
    $n = ($page - 1) * $PAGE_SIZE + 1;
  }

  my($date, $msg, $fact, $sev, $tag, $hname);
  while (($date, $msg, $fact, $sev, $tag, $hname) = $sth->fetchrow_array()) {

    my($fact)      = $factility[$fact]?$factility[$fact]:$fact;
    my($sev1)      = $severity[$sev]?$severity[$sev]:$sev;
    my($bgcolor)   = $bgcolor[$sev]?$bgcolor[$sev]:'MintCream';
    my($fontcolor) = $fontcolor[$sev]?$fontcolor[$sev]:'Black';
    $date =~ s/\..+$//;
#    unless (($device == 177) and ($msg =~ m/mal-attempts detected/)) {
      print "      <TR bgcolor='$bgcolor'>\n";
      print "        <TD><FONT color='$fontcolor'>$n</FONT></TD>\n";
      print "        <TD><FONT color='$fontcolor'>$date</FONT></TD>\n";
      print "        <TD><FONT color='$fontcolor'>$hname</FONT></TD>\n";
      print "        <TD><FONT color='$fontcolor'>$tag</FONT></TD>\n";
      print "        <TD><FONT color='$fontcolor'>$fact</FONT></TD>\n";
      print "        <TD><FONT color='$fontcolor'>$sev1</FONT></TD>\n";
      print "        <TD><FONT color='$fontcolor'>$msg</FONT></TD>\n";
      print "      </TR>\n";
      $n++;
#    }
  }
  print "    </TABLE>\n";
  $sth->finish();

} elsif ($cmd eq 'edit') {

  print_edit_form();

} elsif ($cmd eq 'submit') {

  my($name, $model, $comment);
  $name    = CGI::param('name');
  $model   = CGI::param('model');
  $comment = CGI::param('comment');

  $sth = $dbh->prepare("UPDATE devices SET name=?, model=?, comment=? WHERE id=?");
  $sth->execute($name, $model, $comment, $device);
  $sth->finish();

  print_edit_form();

} elsif ($cmd eq 'none') {
} elsif ($cmd eq 'notfound') {
  print "Логов устройства с таким IP ( $ip ) не найдено.";
} else {
  print "    Ошибка команды\n";
}

print "  </BODY>\n";
print "</HTML>\n";

$dbh->disconnect();


sub print_edit_form {
  $sth = $dbh->prepare("SELECT ip, name, model, comment FROM devices WHERE id=?");
  $sth->execute($device);
  my($ip, $name, $model, $comment) = $sth->fetchrow_array();
  $sth->finish();

  $comment = $comment?$comment:'';

  print "    <H4>Редактирование утсройства $ip</H4>\n";
  print "    <FORM>\n";
  print "      <TABLE>\n";
  print "        <TR><TD>Название</TD><TD><INPUT type='text' name='name' value='$name'></TD></TR>\n";
  print "        <TR><TD>Модель</TD><TD><INPUT type='text' name='model' value='$model'></TD></TR>\n";
  print "        <TR><TD>Комментарий</TD><TD><TEXTAREA name='comment'>$comment</TEXTAREA></TD></TR>\n";
  print "      </TABLE>\n";
  print "      <INPUT type='submit' value='Сохранить'>&nbsp;<INPUT type='reset' value='Отменить'>\n";
  print "      <INPUT type='hidden' name='cmd' value='submit'>\n";
  print "      <INPUT type='hidden' name='device' value='$device'>\n";
  print "    </FORM>\n";
}


# Собирает URL скрипта из его текущего состояния с возможностью перекрыть некоторые параметры.
sub url {
  # Хэш с паракрывающими параметрами
  my($arr)  = shift;

  # Текущее состояние скрипта
  my(%parm) = ('page' => $page, 'device' => $device, 'cmd' => $cmd);

  my($key);

  # Собираем URL начиная с имени скрипта
  my($ret) = $self_name;
  $ret .= '?';

  if ($arr) {
    # Если был передан хэш с перекрытием - то перекрываем параметры.
    foreach $key (keys %$arr) {
      $parm{$key} = $arr->{$key};
    }
  }

  # Формируем GET строку параметров.
  my($s) = '';
  foreach $key (keys %parm) {
    $s .= "&$key=$parm{$key}";
  }

  # Убираем лидирующий '&' и формируем окончательный URL.
  $ret .= substr($s, 1);

  return $ret;
}

# Формирует код строки Всё/Постранично в зависимости от того какой режим у нас сейчас
sub pager_onoff {
  my($pager) = shift;
  if ($page == 0) {
    return str_replace('%u%', url({'page' => 1}), $pager->{'pager'});
  } else {
    return str_replace('%u%', url({'page' => 0}), $pager->{'all'});
  }
}

# Формирует непосредственно HTML код пейджера
sub pager_html {
    my($pager) = shift;
    my($total) = shift;

    my($html) = '';

    my($blocks) = ceil($total / $PAGE_SIZE);

    # Если он вообще нужен
    if ($page != 0) {

      my($pstart, $pend, $larr, $rarr);

      # Начало пейджера
      $html .= $pager->{'begin'};

      # Если кол-во страниц больше окна пейджера, то надо генерировать стрелочки и ограничивать кол-во "кнопок"
      if ($blocks > $WINDOW_SIZE) {

        # Текущая страница в самом начале окна пейджера
        if ($page < ceil($WINDOW_SIZE / 2)) {
          $pstart = 0;
          $pend = $WINDOW_SIZE;
        # Текущая страница в самом конце пейджера
        } elsif ($page > ($blocks - ceil($WINDOW_SIZE / 2))) {
          $pstart = $blocks - $WINDOW_SIZE;
          $pend = $blocks;
        # Иначе, мы гдето в середине страниц
        } else {
          $pstart = $page - ceil($WINDOW_SIZE / 2);
          $pend = $page + ceil($WINDOW_SIZE / 2) - 1;
        }

        # Если текущая страница НЕ самая первая - то генерируем левые стрелочки
        if ($page > 1) {
          $larr  = str_replace('%u%', url({'page' => 1}), $pager->{'first_page'});
          $larr .= str_replace('%u%', url({'page' => $page - 1}), $pager->{'prev_page'});
        } else {
          $larr = '';
        }

        # Если текущая страница НЕ самая последняя - то генерируем правые стрелочки
        if ($page < $blocks) {
          $rarr  = str_replace('%u%', url({'page' => $page + 1}), $pager->{'next_page'});
          $rarr .= str_replace('%u%', url({'page' => $blocks}), $pager->{'last_page'});
        } else {
          $rarr = '';
        }


      # Окно больше, чем есть страниц, значит, не генерируем стрелки а только сами кнопки.
      } else {

        $pstart = 0;
        $pend = $blocks;

        $rarr = '';
        $larr = '';
      }

      # Добиваем левые стрелки (если сгенерировались)
      $html .= $larr;

      # Рисуем сам пейджер со всеми стрелочками.
      my($i, $n);
      for ($i = $pstart; $i < $pend; $i++) {
        $n = $i + 1;
        # Текущая страница, ссылки не будет
        if ($n == $page) {
          $html .= str_replace('%n%', $n, $pager->{'curr_page'});
        } else {
          my($r) = $pager->{'page'};
          $r = str_replace('%u%', url({'page' => $n}), $r);
          $r = str_replace('%n%', $n, $r);
          $html .= $r;
        }
      }

      $html .= $rarr;
      $html .= $pager->{'end'};

    } else {

      $html .= $pager->{'no_pager'};

    }  # if (page != 'all')

    return $html;
}

# Возвращает ограничивающую SQL добавку в соответствии с текуещей страницей.
sub pager_sql {
  my($p) = shift;

  # Если не заказанная страница, то используем текущую.
  if (! $p) {
    $p = $page;
  }

  # Если не весь список - то генерируем ограничивающую добавку
  if ($p != 0) {
    my($start)    = ($p - 1) * $PAGE_SIZE;
    my($blk_size) = $PAGE_SIZE;
    return " LIMIT $blk_size OFFSET $start";
  } else {
    return '';
  }
}

# Эмуляция на perl ф-ции из PHP.
sub str_replace {
  my($cs)   = shift;
  my($repl) = shift;
  my($str)  = shift;

  if ($cs) {
    my($idx) = index($str, $cs);
    if ($idx >= 0 ) {
      substr($str, $idx, length($cs)) = $repl;
    }
  }
  return $str;
}
