#!/usr/local/bin/perl
# Update master server IPs

require 'virtualmin-mailrelay-lib.pl';
&ReadParse();
&error_setup($text{'save_err'});

# Get and check the domain
&can_edit_relay($in{'dom'}) || &error($text{'edit_ecannot'});
$d = &virtual_server::get_domain_by("dom", $in{'dom'});
$d || &error($text{'edit_edomain'});
$relay = &get_relay_destination($in{'dom'});
$relay || &error($text{'edit_erelay'});

# Validate inputs
$in{'relay'} =~ /\S/ || &error($text{'save_enone'});
gethostbyname($in{'relay'}) || &error($text{'save_erelay'});

&ui_print_unbuffered_header(&virtual_server::domain_in($d),
			    $text{'edit_title'}, "");

# Update the mailertable
&$virtual_server::first_print($text{'save_doing'});
&save_relay_destination($in{'dom'}, $in{'relay'});
&$virtual_server::second_print($virtual_server::text{'setup_done'});

if (&can_domain_filter() && defined($in{'filter'})) {
	$old = &get_domain_filter($d->{'dom'});
	if ($in{'filter'} && !$old) {
		# Turn on spam filter
		&$virtual_server::first_print($text{'save_spamon'});
		&save_domain_filter($d->{'dom'}, 1);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	elsif (!$in{'filter'} && $old) {
		# Turn off spam filter
		&$virtual_server::first_print($text{'save_spamoff'});
		&save_domain_filter($d->{'dom'}, 0);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	}

&webmin_log("save", undef, $in{'dom'});
&ui_print_footer("edit.cgi?dom=$in{'dom'}", $text{'edit_return'});

