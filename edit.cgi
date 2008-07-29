#!/usr/local/bin/perl
# Show a form for editing a mail relay domain's destination server

require 'virtualmin-mailrelay-lib.pl';
&ReadParse();

# Get and check the domain
&can_edit_relay($in{'dom'}) || &error($text{'edit_ecannot'});
$d = &virtual_server::get_domain_by("dom", $in{'dom'});
$d || &error($text{'edit_edomain'});
$relay = &get_relay_destination($in{'dom'});
$relay || &error($text{'edit_erelay'});

&ui_print_header(&virtual_server::domain_in($d), $text{'edit_title'}, "");

print &ui_form_start("save.cgi");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'edit_header'}, undef, 2, [ "width=30%" ]);

# Relay destination
print &ui_table_row($text{'edit_relay'},
	&ui_textbox("relay", $relay, 30));

# Filter spam?
if (&can_domain_filter()) {
	print &ui_table_row($text{'edit_filter'},
		&ui_yesno_radio("filter", &get_domain_filter($d->{'dom'})));
	}

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'save'} ] ]);

&ui_print_footer("/", $text{'index'});

