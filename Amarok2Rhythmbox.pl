#! /usr/bin/perl -w

use strict;
use DBI;
use URI::Escape;
use utf8;

my $RB_DB_FILE         = "/home/simon/.local/share/rhythmbox/rhythmdb.xml";
my $RB_LIB_BASE        = "file:///home/simon/Music/";
my $AMAROK_DB_HOST     = "localhost";
my $AMAROK_DB_NAME     = "amarokdb";
my $AMAROK_DB_USER     = "amarokuser";
my $AMAROK_DB_PASSWORD = "amarokpassword";
my $AMAROK_LIB_BASE    = "./home/simon/Music/";

print "Connecting to Rhythmbox DB...";
my $dbhRB = DBI->connect('dbi:AnyData(RaiseError=>1):') || die("FAIL\n");
$dbhRB->func('rb_tracks', 'XML', $RB_DB_FILE, {record_tag => "entry", col_map => ["location", "rating"]}, 'ad_catalog');
print "DONE\n";

print "Connecting to Amarok DB ($AMAROK_DB_NAME, $AMAROK_DB_HOST)...";
my $dbhAmarok = DBI->connect("dbi:mysql:$AMAROK_DB_NAME", $AMAROK_DB_USER, $AMAROK_DB_PASSWORD, {RaiseError => 0, AutoCommit => 1}) || die("FAIL\n");
$dbhAmarok->{'mysql_enable_utf8'} = 1;
$dbhAmarok->do('SET NAMES utf8;');
print "DONE\n";

print "Fetching Rhythmbox track list...";
my $sthRBTracks = $dbhRB->prepare("SELECT * FROM rb_tracks") || die("Unable to prepare Rhythmbox tracks select query");
$sthRBTracks->execute() || die("Unable to execute Rhythmbox tracks select query");
print "DONE\n";

my $sthAmarokTrack = $dbhAmarok->prepare("SELECT statistics.rating as rating FROM urls JOIN statistics ON urls.id = statistics.url WHERE urls.rpath LIKE ?") || die("Unable to prepare SELECT query for Amarok DB");
my $sthRBUpdate    = $dbhRB->prepare("UPDATE rb_tracks SET rating = ? WHERE location LIKE ?") || die("Unable to prepare UPDATE statement for Rhythmbox DB");

while (my $row = $sthRBTracks->fetchrow_hashref())
{
	my $uri_rb = $row->{"location"};
	my $uri = uri_unescape($uri_rb);
	$uri =~ s/^$RB_LIB_BASE//;
	$sthAmarokTrack->bind_param(1, "\%$uri\%");
	$sthAmarokTrack->execute() || die("Unable to execute Amarok track ID query");
	if ($sthAmarokTrack->rows > 0)
	{
		if (my $rowAmarok = $sthAmarokTrack->fetchrow_hashref())
		{
			my $rating = $rowAmarok->{'rating'} / 2;
			print "Updating $uri\t(rating: $rating)... \n";
			$sthRBUpdate->bind_param(1, $rating);
			$sthRBUpdate->bind_param(2, $uri_rb);
			if ($sthRBUpdate->execute())
			{
				($sthRBUpdate->rows == 1) ? print "DONE\n" : print "FAIL\n";
			}
			else
			{
				print STDERR "Error updating $uri\n";
			}
			$sthRBUpdate->finish();
		}
		else
		{
			print STDERR "Track not found: $uri\n";
		}
	}
	else
	{
		print STDERR "Track not found: $uri\n";
	}
}
$sthRBUpdate    = undef;
$sthAmarokTrack = undef;
$sthRBTracks    = undef;

print "Closing Amarok DB connection...";
$dbhAmarok->disconnect();
print "DONE\n";

print "Closing Rhythmbox DB connection...";
$dbhRB->disconnect();
print "DONE\n";

