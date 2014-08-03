#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

package Dicom::Handler;

# Pragmas.
use strict;
use warnings;

# Modules.
use English;

# Constructor.
sub new {
	my ($type, %params) = @_;
	return bless {
		%params,
		'table_flag' => 0,
		'td_index' => -1,
		'td' => ['', '', '', '', '', ''],
		'td_ok' => 0,
		'tr_index' => 0,
	}, $type;
}

# Start element.
sub start_element {
	my ($self, $element) = @_;
	if (exists $element->{'Attributes'}
		&& exists $element->{'Attributes'}->{'{}label'}
		&& $element->{'Attributes'}->{'{}label'}->{'Value'} eq '6-1') {

		$self->{'table_flag'} = 1;
	}
	if (! $self->{'table_flag'}) {
		return;
	}

	# Right td.
	if (! $self->{'td_ok'}) {
		return;
	}
	if ($element->{'Name'} eq 'td') {
		$self->{'td_index'}++;
	}

	# XREF.
	if ($element->{'Name'} eq 'xref') {
		my $note = $element->{'Attributes'}->{'{}linkend'}->{'Value'};
		$note =~ s/^note_//ms;
		$note =~ s/_/\./gms;
		$self->{'td'}->[$self->{'td_index'}] .= $note;
	}
	return;
}

# End element.
sub end_element {
	my ($self, $element) = @_;
	if (! $self->{'table_flag'}) {
		return;
	}
	if ($element->{'Name'} eq 'table') {
		$self->{'table_flag'} = 0;
	}

	# Right tr element.
	if ($element->{'Name'} eq 'tr') {
		if ($self->{'tr_index'} == 0) {
			$self->{'tr_index'} = 1;
			$self->{'td_ok'} = 1;
			return;
		}
		my ($tag, $name, $keyword, $vr, $vm, $retired)
			= @{$self->{'td'}};
		my ($tag_group, $tag_number) = $tag
			=~ m/^\(([\d\w]+),([\d\w]+)\)$/ms;
		$keyword =~ s/\x{200b}//gms;
		my $ret_ar = eval {
			$self->{'dt'}->execute('SELECT COUNT(*) FROM data '.
				'WHERE Tag_group = ? AND Tag_number = ?',
				$tag_group, $tag_number);
		};
		if ($EVAL_ERROR || ! @{$ret_ar}
			|| ! exists $ret_ar->[0]->{'count(*)'}
			|| ! defined $ret_ar->[0]->{'count(*)'}
			|| $ret_ar->[0]->{'count(*)'} == 0) {

			print "($tag_group,$tag_number): $keyword\n";
			$self->{'dt'}->insert({
				'Tag_group' => $tag_group,
				'Tag_number' => $tag_number,
				'Name' => $name,
				'Keyword' => $keyword,
				'VR' => $vr,
				'VM' => $vm,
				'Retired' => $retired,
			});
		}
		$self->{'dt'}->create_index(['Tag_group', 'Tag_number'],
			'data', 1, 1);
		$self->{'td'} = ['', '', '', '', '', ''];
		$self->{'td_index'} = -1;
	}
	return;
}

# Characters.
sub characters {
	my ($self, $characters) = @_;
	if (! $self->{'table_flag'}) {
		return;
	}

	# Skip blank data.
	if ($characters->{'Data'} =~ m/^\s*$/ms) {
		return;
	}

	# Right td.
	if (! $self->{'td_ok'}) {
		return;
	}
	$self->{'td'}->[$self->{'td_index'}] .= $characters->{'Data'};
	return;
}

package main;

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Encode qw(decode_utf8 encode_utf8);
use English;
use File::Temp qw(tempfile);
use LWP::UserAgent;
use URI;
use XML::SAX::Expat;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URI of service.
my $base_uri = URI->new('ftp://medical.nema.org/medical/dicom/2014a/source/docbook/part06/part06.xml');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get base root.
print 'Page: '.$base_uri->as_string."\n";
my $xml_file = get_file($base_uri);
my $h = Dicom::Handler->new(
	'dt' => $dt,
);
my $p = XML::SAX::Expat->new('Handler' => $h);
$p->parse_file($xml_file);
unlink $xml_file;

# Get file
sub get_file {
	my $uri = shift;
	my (undef, $tempfile) = tempfile();
	my $get = $ua->get($uri->as_string,
		':content_file' => $tempfile,
	);
	if ($get->is_success) {
		return $tempfile;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
}

# Removing trailing whitespace.
sub remove_trailing {
	my $string_sr = shift;
	${$string_sr} =~ s/^\s*//ms;
	${$string_sr} =~ s/\s*$//ms;
	return;
}
