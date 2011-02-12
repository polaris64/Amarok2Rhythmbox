#! /usr/bin/perl -w

use strict;
use DBI;
use XML::LibXML;
use URI::Escape;
use utf8;

my $RB_DB_FILE         = $ENV{'HOME'} ."/.local/share/rhythmbox/rhythmdb.xml";
my $RB_LIB_BASE        = "file:///home/simon/Music/";
my $AMAROK_DB_HOST     = "localhost";
my $AMAROK_DB_NAME     = "amarokdb";
my $AMAROK_DB_USER     = "amarokuser";
my $AMAROK_DB_PASSWORD = "amarokpassword";
my $AMAROK_LIB_BASE    = "./home/simon/Music/";

print "Opening Rhythmbox DB... ";
my $libxml = XML::LibXML->new();
my $xmlRB  = $libxml->parse_file($RB_DB_FILE);
print "DONE\n";

print "Connecting to Amarok DB ($AMAROK_DB_NAME, $AMAROK_DB_HOST)...";
my $dbhAmarok = DBI->connect("dbi:mysql:$AMAROK_DB_NAME", $AMAROK_DB_USER, $AMAROK_DB_PASSWORD, {RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1}) || die("FAIL\n");
$dbhAmarok->do('SET NAMES utf8;');
print "DONE\n";

my $sthAmarokTrack = $dbhAmarok->prepare("SELECT statistics.rating as rating FROM urls JOIN statistics ON urls.id = statistics.url WHERE urls.rpath LIKE ?") || die("Unable to prepare SELECT query for Amarok DB");

foreach my $trackRB ($xmlRB->findnodes('/rhythmdb/entry[@type="song"]'))
{
	my $uri_rb = $trackRB->findnodes('./location')->to_literal;
	my $uri = uri_unescape($uri_rb);
	$uri =~ s/^$RB_LIB_BASE//;
	utf8::decode($uri) if (utf8::is_utf8($uri));

	$sthAmarokTrack->bind_param(1, "\%$uri\%");
	$sthAmarokTrack->execute() || die("Unable to execute Amarok track ID query");
	if ($sthAmarokTrack->rows > 0)
	{
		if (my $rowAmarok = $sthAmarokTrack->fetchrow_hashref())
		{
			my $rating = $rowAmarok->{'rating'} / 2;
			print "Updating $uri\t(rating: $rating)... ";
			my($rating_node) = $trackRB->findnodes('./rating');
			$trackRB->removeChild($rating_node) if (defined($rating_node));
			$rating_node = $xmlRB->createElement('rating');
			$rating_node->appendTextNode($rating);
			$trackRB->appendChild($rating_node);
			print "DONE\n";
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

print "Writing new Rhythmbox DB... ";
$xmlRB->toFile($RB_DB_FILE);
print "DONE\n";

$sthAmarokTrack = undef;

print "Closing Amarok DB connection...";
$dbhAmarok->disconnect();
print "DONE\n";

$xmlRB  = undef;
$libxml = undef;

