# XXX docs
#	XXX mimedefang setup (filter_recipient, -t flag, general install)
# XXX mailscanner support?
# XXX add to repos
# XXX quarantine management, per domain
# XXX what happens to spam?
# XXX announce on www.webmin.com, send to michael

require 'virtualmin-mailrelay-lib.pl';
$input_name = $module_name;
$input_name =~ s/[^A-Za-z0-9]/_/g;

# feature_name()
# Returns a short name for this feature
sub feature_name
{
return $text{'feat_name'};
}

# feature_losing(&domain)
# Returns a description of what will be deleted when this feature is removed
sub feature_losing
{
return $text{'feat_losing'};
}

# feature_label(in-edit-form)
# Returns the name of this feature, as displayed on the domain creation and
# editing form
sub feature_label
{
return $text{'feat_label'};
}

# feature_hlink(in-edit-form)
# Returns a help page linked to by the label returned by feature_label
sub feature_hlink
{
return 'feat';
}

# feature_check()
# Returns undef if all the needed programs for this feature are installed,
# or an error message if not
sub feature_check
{
if (!$virtual_server::config{'mail'}) {
	return $text{'feat_echeckmail'};
	}
&virtual_server::require_mail();
if ($virtual_server::config{'mail_system'} == 0) {
	# Check for Postfix transport map
	local $trans = &postfix::get_real_value("transport_maps");
	$trans || return $text{'feat_echecktrans'};
	if (defined(&postfix::can_access_map)) {
		local @tv = &postfix::get_maps_types_files("transport_maps");
		foreach my $tv (@tv) {
			if (!&postfix::supports_map_type($tv->[0])) {
				return &text('feat_echeckmap',
					     "$tv->[0]:$tv->[1]");
				}
			local $err = &postfix::can_access_map(@$tv);
			if ($err) {
				return &text('feat_echeckmapaccess',
					     "$tv->[0]:$tv->[1]", $err);
				}
			}
		}
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Check for Sendmail mailertable
	&foreign_require("sendmail", "mailers-lib.pl");
	local ($mdbm, $mtype) = &sendmail::mailers_dbm(
					&sendmail::get_sendmailcf());
	if (!$mdbm) {
		return $text{'feat_echeckmailertable'};
		}
	}
else {
	return $text{'feat_echeck'};
	}

# Check spam filter
return &check_spam_filter();
}

# feature_depends(&domain)
# Returns undef if all pre-requisite features for this domain are enabled,
# or an error message if not.
# Checks for a default master IP address in template.
sub feature_depends
{
local ($d) = @_;
return $text{'feat_email'} if ($d->{'mail'});
local $tmpl = &virtual_server::get_template($d->{'template'});
local $mip = $tmpl->{$module_name."server"};
return $mip eq '' || $mip eq 'none' ? $text{'feat_eserver'} : undef;
}

# feature_clash(&domain)
# Returns undef if there is no clash for this domain for this feature, or
# an error message if so.
# Checks for a mailertable entry on Sendmail
sub feature_clash
{
local ($d) = @_;
&virtual_server::require_mail();
if ($virtual_server::config{'mail_system'} == 0) {
	# Check for transport entry
	local $trans = &postfix::get_maps("transport_maps");
	local ($clash) = grep { $_->{'name'} eq $_[0]->{'dom'} } @$trans;
	if ($clash) {
		return $text{'feat_eclashtrans'};
		}
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Check for mailertable entry
	&foreign_require("sendmail", "mailers-lib.pl");
	local $mfile = &sendmail::mailers_file(&sendmail::get_sendmailcf());
	local @mailers = &sendmail::list_mailers($mfile);
	local ($clash) = grep { $_->{'domain'} eq $_[0]->{'dom'} } @mailers;
	if ($clash) {
		return $text{'feat_eclashmailertable'};
		}
	}
return undef;
}

# feature_suitable([&parentdom], [&aliasdom], [&subdom])
# Returns 1 if some feature can be used with the specified alias,
# parent and sub domains.
# Doesn't make sense for alias domains.
sub feature_suitable
{
local ($parentdom, $aliasdom, $subdom) = @_;
return !$aliasdom;
}

# feature_setup(&domain)
# Called when this feature is added, with the domain object as a parameter.
# Adds a mailertable or transport entry
sub feature_setup
{
local ($d) = @_;
local $tmpl = &virtual_server::get_template($d->{'template'});
local $server = $tmpl->{$module_name."server"};
&$virtual_server::first_print($text{'setup_relay'});
if (!$server) {
	&$virtual_server::second_print($text{'setup_eserver'});
	return 0;
	}
&obtain_lock_virtualmin_mailrelay($d);

# Add relay for domain, using appropriate mail server
if ($virtual_server::config{'mail_system'} == 0) {
	# Add SMTP transport
	local $map = { 'name' => $d->{'dom'},
		       'value' => "smtp:[$server]" };
	&postfix::create_mapping("transport_maps", $map);
	&postfix::regenerate_any_table("transport_maps");
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Add mailertable entry
	local $map = { 'domain' => $d->{'dom'},
		       'mailer' => 'smtp',
		       'dest' => "[$server]" };
	&foreign_require("sendmail", "mailers-lib.pl");
	local $conf = &sendmail::get_sendmailcf();
	local ($mdbm, $mtype) = &sendmail::mailers_dbm($conf);
	local $mfile = &sendmail::mailers_file($conf);
	&sendmail::create_mailer($map, $mfile, $mdbm, $mtype);
	}

# Allow this system to relay
&virtual_server::setup_secondary_mx($d->{'dom'});

# Setup spam filter
if (&can_domain_filter() && $tmpl->{$module_name."filter"} eq "yes") {
	&save_domain_filter($d->{'dom'}, 1);
	}

&release_lock_virtualmin_mailrelay($d);
&$virtual_server::second_print(&text('setup_done', $server));

# Add DNS MX record for this domain, pointing to this system
if ($d->{'dns'}) {
	&virtual_server::require_bind();
	if (defined(&virtual_server::obtain_lock_dns)) {
		&virtual_server::obtain_lock_dns($d, 1);
		}

	local $z = &virtual_server::get_bind_zone($d->{'dom'});
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	local $zonefile = &bind8::make_chroot($fn);
	local @recs = &bind8::read_zone_file($fn, $d->{'dom'});
	local ($mx) = grep { $_->{'type'} eq 'MX' &&
			     $_->{'name'} eq $d->{'dom'}."." ||
			     $_->{'type'} eq 'A' &&
			     $_->{'name'} eq "mail.".$d->{'dom'}."." } @recs;
	if (!$mx) {
		&$virtual_server::first_print(
			$virtual_server::text{'save_dns4'});
		local $ip = $d->{'dns_ip'} || $d->{'ip'};
		&virtual_server::create_mx_records($fn, $d, $ip);
		&bind8::bump_soa_record($fn, \@recs);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		&virtual_server::register_post_action(
			\&virtual_server::restart_bind);
		}

	if (defined(&virtual_server::release_lock_dns)) {
		&virtual_server::release_lock_dns($d, 1);
		}
	}

# All done
return 1;
}

# feature_modify(&domain, &olddomain)
# Called when a domain with this feature is modified.
# Renames the mailertable or transport entry
sub feature_modify
{
local ($d, $oldd) = @_;
if ($d->{'dom'} ne $oldd->{'dom'}) {
	&$virtual_server::first_print($text{'modify_relay'});
	&obtain_lock_virtualmin_mailrelay($d);

	# Modify for domain, using appropriate mail server
	if ($virtual_server::config{'mail_system'} == 0) {
		# Change SMTP transport
		local $trans = &postfix::get_maps("transport_maps");
		local ($old) = grep { $_->{'name'} eq $oldd->{'dom'} } @$trans;
		if ($old) {
			local $nw = { %$old };
			$nw->{'name'} = $d->{'dom'};
			&postfix::modify_mapping("transport_maps", $old, $nw);
			&postfix::regenerate_any_table("transport_maps");
			&$virtual_server::second_print(
				$virtual_server::text{'setup_done'});
			}
		else {
			&$virtual_server::second_print(
				$text{'modify_etransport'});
			}
		}
	elsif ($virtual_server::config{'mail_system'} == 1) {
		# Change mailertable entry
		&foreign_require("sendmail", "mailers-lib.pl");
		local $conf = &sendmail::get_sendmailcf();
		local $mfile = &sendmail::mailers_file($conf);
		local ($mdbm, $mtype) = &sendmail::mailers_dbm($conf);
		local @mailers = &sendmail::list_mailers($mfile);
		local ($old) = grep { $_->{'domain'} eq $oldd->{'dom'} }
				    @mailers;
		if ($old) {
			local $nw = { %$old };
			$nw->{'domain'} = $d->{'dom'};
			&sendmail::modify_mailer($old, $nw, $mfile,
						 $mdbm, $mtype);
			&$virtual_server::second_print(
				$virtual_server::text{'setup_done'});
			}
		else {
			&$virtual_server::second_print(
				$text{'modify_emailertable'});
			}
		}

	# Fix up relaying
	&virtual_server::setup_secondary_mx($d->{'dom'});
	&virtual_server::delete_secondary_mx($oldd->{'dom'});

	# Change domain name to filter
	if (&can_domain_filter()) {
		local $filter = &get_domain_filter($oldd->{'dom'});
		&save_domain_filter($oldd->{'dom'}, 0);
		&save_domain_filter($d->{'dom'}, $filter);
		}

	# All done
	&release_lock_virtualmin_mailrelay($d);
	return 1;
	}
return 1;
}

# feature_delete(&domain)
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
local ($d) = @_;
&$virtual_server::first_print($text{'delete_relay'});
&obtain_lock_virtualmin_mailrelay($d);

# Delete for domain, using appropriate mail server
if ($virtual_server::config{'mail_system'} == 0) {
	# Delete SMTP transport
	local $trans = &postfix::get_maps("transport_maps");
	local ($old) = grep { $_->{'name'} eq $d->{'dom'} } @$trans;
	if ($old) {
		&postfix::delete_mapping("transport_maps", $old);
		&postfix::regenerate_any_table("transport_maps");
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	else {
		&$virtual_server::second_print($text{'modify_etransport'});
		}
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Change mailertable entry
	&foreign_require("sendmail", "mailers-lib.pl");
	local $conf = &sendmail::get_sendmailcf();
	local $mfile = &sendmail::mailers_file($conf);
	local ($mdbm, $mtype) = &sendmail::mailers_dbm($conf);
	local @mailers = &sendmail::list_mailers($mfile);
	local ($old) = grep { $_->{'domain'} eq $d->{'dom'} }
			    @mailers;
	if ($old) {
		&sendmail::delete_mailer($old, $mfile, $mdbm, $mtype);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	else {
		&$virtual_server::second_print($text{'modify_emailertable'});
		}
	}

# Turn off relaying
&virtual_server::delete_secondary_mx($d->{'dom'});

# Turn off spam
if (&can_domain_filter()) {
	&save_domain_filter($d->{'dom'}, 0);
	}
&release_lock_virtualmin_mailrelay($d);

# Remove MX records, if any 
if ($d->{'dns'}) {
	local $z = &virtual_server::get_bind_zone($d->{'dom'});
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	local $zonefile = &bind8::make_chroot($fn);
	local @recs = &bind8::read_zone_file($fn, $newzonename);
	local @mx = grep { $_->{'type'} eq 'MX' &&
			   $_->{'name'} eq $_[0]->{'dom'}."." ||
			   $_->{'type'} eq 'A' &&
			   $_->{'name'} eq "mail.".$_[0]->{'dom'}."." } @recs;
	if (@mx) {
		&$virtual_server::first_print(
			$virtual_server::text{'save_dns5'});
		foreach my $r (reverse(@mx)) {
			&bind8::delete_record($fn, $r);
			}
		&bind8::bump_soa_record($fn, \@recs);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		&virtual_server::register_post_action(
			\&virtual_server::restart_bind);
		}
	}

# All done
return 1;
}

# feature_import(domain-name, user-name, db-name)
# Returns 1 if this feature is already enabled for some domain being imported,
# or 0 if not
sub feature_import
{
local ($dname, $user, $db) = @_;
local $fake = { 'dom' => $dname };
local $err = &feature_clash($fake);
return $err ? 1 : 0;
}

# feature_links(&domain)
# Returns an array of link objects for webmin modules for this feature
sub feature_links
{
local ($d) = @_;
return ( { 'mod' => $module_name,
           'desc' => $text{'links_link'},
           'page' => 'edit.cgi?dom='.$d->{'dom'},
           'cat' => 'server',
         } );
}

# feature_webmin(&main-domain, &all-domains)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
local @doms = map { $_->{'dom'} } grep { $_->{$module_name} } @{$_[1]};
if (@doms) {
        return ( [ $module_name,
                   { 'dom' => join(" ", @doms),
                     'noconfig' => 1 } ] );
        }
else {
        return ( );
        }
}

# feature_backup(&domain, file, &opts, &all-opts)
# Called to backup this feature for the domain to the given file. Must return 1
# on success or 0 on failure.
# Just saves the relay dest and spam flag
sub feature_backup
{
local ($d, $file) = @_;
&$virtual_server::first_print($text{'backup_conf'});
local %binfo;
$binfo{'dest'} = &get_relay_destination($d->{'dom'});
if (&can_domain_filter()) {
	$binfo{'filter'} = &get_domain_filter($d->{'dom'});
	}
&write_file($file, \%binfo);
&$virtual_server::second_print($virtual_server::text{'setup_done'});
return 1;
}

# feature_restore(&domain, file, &opts, &all-opts)
# Called to restore this feature for the domain from the given file. Must
# return 1 on success or 0 on failure.
# Just re-sets the old relay dest and spam filter
sub feature_restore
{
local ($d, $file) = @_;
&$virtual_server::first_print($text{'restore_conf'});
&obtain_lock_virtualmin_mailrelay($d);
local %binfo;
&read_file($file, \%binfo);
if ($binfo{'dest'} ne '') {
	&save_relay_destination($d->{'dom'}, $binfo{'dest'});
	}
if ($binfo{'filter'} ne '' && &can_domain_filter()) {
	&save_domain_filter($d->{'dom'}, $binfo{'filter'});
	}
&release_lock_virtualmin_mailrelay($d);
&$virtual_server::second_print($virtual_server::text{'setup_done'});
return $rv;
}

# feature_backup_name()
# Returns a description for what is backed up for this feature
sub feature_backup_name
{
return $text{'backup_name'};
}

# feature_validate(&domain)
# Checks if this feature is properly setup for the virtual server, and returns
# an error message if any problem is found.
# Checks that the mailertable or transport entry exists
sub feature_validate
{
local ($d) = @_;
if (!&feature_clash($d)) {
	return $virtual_server::config{'mail_system'} == 0 ?
		$text{'validate_etransport'} :
		$text{'validate_emailertable'};
	}
return undef;
}

# template_input(&template)
# Returns HTML for editing per-template options for this plugin
sub template_input
{
local ($tmpl) = @_;

# Default SMTP server input
local $v = $tmpl->{$module_name."server"};
$v = "none" if (!defined($v) && $tmpl->{'default'});
local $rv;
$rv .= &ui_table_row($text{'tmpl_server'},
	&ui_radio($input_name."_mode",
		$v eq "" ? 0 : $v eq "none" ? 1 : 2,
		[ $tmpl->{'default'} ? ( ) : ( [ 0, $text{'default'} ] ),
		  [ 1, $text{'tmpl_notset'} ],
		  [ 2, $text{'tmpl_host'} ] ])."\n".
	&ui_textbox($input_name, $v eq "none" ? undef : $v, 30));

# Default filter mode, if possible
if (&can_domain_filter()) {
	local $v = $tmpl->{$module_name."filter"};
	$v = "no" if (!defined($v) && $tmpl->{'default'});
	$rv .= &ui_table_row($text{'tmpl_filter'},
	    &ui_radio($input_name."_filter",
		$v eq "" ? 0 : $v eq "no" ? 1 : 2,
		[ $tmpl->{'default'} ? ( ) : ( [ 0, $text{'default'} ] ),
		  [ 2, $text{'yes'} ],
		  [ 1, $text{'no'} ] ]));
	}

return $rv;
}

# template_parse(&template, &in)
# Updates the given template object by parsing the inputs generated by
# template_input. All template fields must start with the module name.
sub template_parse
{
local ($tmpl, $in) = @_;

# Parse SMTP server field
if ($in->{$input_name.'_mode'} == 0) {
        $tmpl->{$module_name."server"} = "";
        }
elsif ($in->{$input_name.'_mode'} == 1) {
        $tmpl->{$module_name."server"} = "none";
        }
else {
	gethostbyname($in->{$input_name}) ||
		&error($text{'tmpl_emaster'});
        $tmpl->{$module_name."server"} = $in->{$input_name};
        }

# Parse filter field
if (defined($in->{$input_name."_filter"})) {
	$tmpl->{$module_name."filter"} =
		$in->{$input_name."_filter"} == 0 ? undef :
		$in->{$input_name."_filter"} == 1 ? "no" : "yes";
	}
}

1;

