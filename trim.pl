#!/usr/bin/perl -w

use DBI;

# имя базы данных
$dbname = 'logs';
# имя пользователя
$username = 'loguser';
# пароль
$password = 'password';
# имя или IP адрес сервера
$dbhost = 'localhost';

$dbh = DBI->connect("dbi:MariaDB:dbname=$dbname;host=$dbhost","$username","$password", {PrintError => 1});


# Удаляем старые логи
$sth = $dbh->prepare("DELETE FROM logs WHERE date < DATE_SUB(CURDATE(), INTERVAL 3 month)");
$sth->execute();
$sth->finish();

$dbh->disconnect();
