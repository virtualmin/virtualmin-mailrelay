# XXX support Sendmail and Postfix
# XXX spam filtering optional
# XXX add DNS records
# XXX for sendmail, need to add to local domains?

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
	# XXX check spam filter?
	return undef;
	}
elsif ($virtual_server::config{'mail_system'} == 1) {
	# Check for Sendmail mailertable
	&foreign_require("sendmail", "mailers-lib.pl");
	local ($mdbm, $mtype) = &sendmail::mailers_dbm(
					&sendmail::get_sendmailcf());
	if (!$mdbm) {
		return $text{'feat_echeckmailertable'};
		}
	# XXX check milter
	return undef;
	}
else {
	return $text{'feat_echeck'};
	}
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
	local $mfile = &mailers_file(&sendmail::get_sendmailcf());
	local @mailers = &list_mailers($mfile);
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
if (defined(&virtual_server::obtain_lock_mail)) {
	&virtual_server::obtain_lock_mail($d);
	}

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
	&foreign_require("sendmail", "mailers-lib.pl");
	local $conf = &sendmail::get_sendmailcf();
	local ($mdbm, $mtype) = &sendmail::mailers_dbm($conf);
	local $mfile = &mailers_file($conf);
	&sendmail::create_mailer($map, $mfile, $mdbm, $mtype);
	}

# Setup spam filter
# XXX

if (defined(&virtual_server::release_lock_mail)) {
	&virtual_server::release_lock_mail($d);
	}
&$virtual_server::second_print(&text('setup_done', $server));

# Add DNS MX record for this domain, pointing to this system
&virtual_server::require_dns();
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
	&$virtual_server::first_print($virtual_server::text{'save_dns4'});
	local $ip = $d->{'dns_ip'} || $d->{'ip'};
	&virtual_server::create_mx_records($fn, $d, $ip);
	&bind8::bump_soa_record($fn, \@recs);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	&virtual_server::register_post_action(\&virtual_server::restart_bind);
	}

if (defined(&virtual_server::release_lock_dns)) {
	&virtual_server::release_lock_dns($d, 1);
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
	&$virtual_server::first_print($text{'modify_bind'});

	if (defined(&virtual_server::obtain_lock_dns)) {
		&virtual_server::obtain_lock_dns($d, 1);
		}

	# Get the zone object
	local $z = &virtual_server::get_bind_zone($oldd->{'dom'});
	if ($z) {
		# Rename records file, for real and in .conf
		local $file = &bind8::find("file", $z->{'members'});
		local $fn = $file->{'values'}->[0];
		$nfn = $fn;
                $nfn =~ s/$oldd->{'dom'}/$d->{'dom'}/;
                if ($fn ne $nfn) {
                        &rename_logged(&bind8::make_chroot($fn),
                                       &bind8::make_chroot($nfn))
                        }
                $file->{'values'}->[0] = $nfn;
                $file->{'value'} = $nfn;

                # Change zone in .conf file
                $z->{'values'}->[0] = $d->{'dom'};
                $z->{'value'} = $d->{'dom'};
                &bind8::save_directive(&bind8::get_config_parent(),
                                       [ $z ], [ $z ], 0);
                &flush_file_lines();

		# Clear zone names caches
		unlink($bind8::zone_names_cache);
		undef(@bind8::list_zone_names_cache);
		}
	else {
		&$virtual_server::second_print(
			$virtual_server::text{'save_nobind'});
		}

	if (defined(&virtual_server::release_lock_dns)) {
		&virtual_server::release_lock_dns($d, 1);
		}

	# All done
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	return 1;
	}
return 1;
}

# feature_delete(&domain)
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
local ($d) = @_;
&$virtual_server::first_print($text{'delete_bind'});

if (defined(&virtual_server::obtain_lock_dns)) {
	&virtual_server::obtain_lock_dns($d, 1);
	}

# Get the zone object
local $z = &virtual_server::get_bind_zone($d->{'dom'});
if ($z) {
	# Delete records file
	local $file = &bind8::find("file", $z->{'members'});
	if ($file) {
		local $zonefile =
		    &bind8::make_chroot($file->{'values'}->[0]);
		&unlink_file($zonefile);
		}

	# Delete from .conf file
	local $rootfile = &bind8::make_chroot($z->{'file'});
	local $lref = &read_file_lines($rootfile);
	splice(@$lref, $z->{'line'}, $z->{'eline'} - $z->{'line'} + 1);
	&flush_file_lines($z->{'file'});

	# Clear zone names caches
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);

	&virtual_server::register_post_action(\&virtual_server::restart_bind);
	}
else {
	&$virtual_server::second_print($virtual_server::text{'save_nobind'});
	}

if (defined(&virtual_server::release_lock_dns)) {
	&virtual_server::release_lock_dns($d, 1);
	}

# All done
&$virtual_server::second_print($virtual_server::text{'setup_done'});
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
# Saves the named.conf block for this domain.
sub feature_backup
{
# XXX what needs to be done here?
local ($d, $file) = @_;
&$virtual_server::first_print($text{'backup_conf'});
local $z = &virtual_server::get_bind_zone($d->{'dom'});
if ($z) {
	local $lref = &read_file_lines($z->{'file'}, 1);
	local $dstlref = &read_file_lines($file);
	@$dstlref = @$lref[$z->{'line'} .. $z->{'eline'}];
	&flush_file_lines($file);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	return 1;
	}
else {
	&$virtual_server::second_print($virtual_server::text{'backup_dnsnozone'});
	return 0;
	}
}

# feature_restore(&domain, file, &opts, &all-opts)
# Called to restore this feature for the domain from the given file. Must
# return 1 on success or 0 on failure
sub feature_restore
{
# XXX what needs to be done here?
local ($d, $file) = @_;
&$virtual_server::first_print($text{'restore_conf'});

if (defined(&virtual_server::obtain_lock_dns)) {
	&virtual_server::obtain_lock_dns($d, 1);
	}

local $z = &virtual_server::get_bind_zone($d->{'dom'});
local $rv;
if ($z) {
	local $lref = &read_file_lines($z->{'file'});
	local $srclref = &read_file_lines($file, 1);
	splice(@$lref, $z->{'line'}, $z->{'eline'}-$z->{'line'}+1, @$srclref);
	&flush_file_lines($z->{'file'});

	&virtual_server::register_post_action(\&virtual_server::restart_bind);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	$rv = 1;
	}
else {
	&$virtual_server::second_print(
		$virtual_server::text{'backup_dnsnozone'});
	$rv = 0;
	}

if (defined(&virtual_server::release_lock_dns)) {
	&virtual_server::release_lock_dns($d, 1);
	}
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
# Checks if the zone exists and is a slave.
sub feature_validate
{
# XXX check that mailertable entry exists
local ($d) = @_;
local $z = &virtual_server::get_bind_zone($d->{'dom'});
if ($z) {
	local $type = &bind8::find("type", $z->{'members'});
	if ($type && ($type->{'values'}->[0] eq 'slave' ||
		      $type->{'values'}->[0] eq 'stub')) {
		return undef;
		}
	return $text{'validate_etype'};
	}
return $text{'validate_ezone'};
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
}

1;

