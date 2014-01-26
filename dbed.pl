#!/usr/bin/perl
# DBED - Concise, comprehensive, configurable user oriented SQL Database editor.
# Intended as an easy solution for providing basic data maintenance functions to site maintainers.
# Lets the developer drop-in a general editor rather than building custom ones for back-end tables.
# Created by Andrew Bedno 2001.11.20 Chicago IL USA

# To install the Perl DBI module run "ppm install DBI" then "ppm install DBD-mysql"
use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);

# CONFIGURATION.
# Fill in the database, user and password below.
$DB_INIT = "DBI:mysql:database=databasename";
$DB_LOGIN = "login";
$DB_PASSWORD = "password";
# Enter single (or comma separated list of) table names this editor will serve.
@TABLES = ('tablename');
# Specify default table to open in browse.
$TABLE_DEFAULT = 'tablename';
# All configs below are indexed by table name. Use one copy of each config row per table.
$TABLE_NAME{'tablename'} = 'full name of table';
$TABLE_PREFIX{'tablename'} = 'common prepended tablename part if any';
# Column configs are comma separated field names.
# Enter names of columns shown in browse. Use * for all fields.
$COLS_VIEW{'tablename'} = 'fieldname[,...]';
# Enter names of columns shown in edit. Use * for all fields.
$COLS_EDIT{'tablename'} = 'fieldname[,...]';
# Enter names of column(s) used as key(s) for edit/del.  Must also be in VIEW field set.
$COLS_KEYS{'tablename'} = 'fieldname[,...]';

# Set to C to confirm deletions, or D to delete without confirmation.
$CONFIRM_DELETE = 'c';
$MAX_RECS_PERPAGE = 150;
$MAX_PAGES = 999;
# Set to amount of recent SQL to also log.  Set high in case of diagnostic need.
$writesqllog_bite = 10000;

# Constants.
%TYPES=(1 => "char", 2 => "numeric", 3 => "decimal", 4 => "integer", 5 => "smallint", 6 => "float", 7 => "real", 8 => "double", 9 => "date", 10=> "time", 11=> "timestamp", 12=> "varchar", -1=> "longvarchar", -2=> "binary", -3=> "varbinary", -4=> "longvarbinary", -5=> "bigint", -6=> "tinyint", -7=> "bit", -8=> "wchar", -9=> "wvarchar", -10=>"wlongvarchar");
$numeric_types = ' decimal numeric integer smallint bigint tinyint ';

$tds = '<font face=Arial size=2 color=black>';
$tde = '</font>';
$mode_names{'e'} = 'EDIT';
$mode_names{'s'} = 'SAVE';
$mode_names{'n'} = 'NEW';
$mode_names{'a'} = 'ADD';
$mode_names{'c'} = 'CONFIRM';
$mode_names{'d'} = 'DELETE';
$mode_names{'b'} = 'BROWSE';
$in_browse = 0;

# Collect parameters.
&GetFormInput;
$currtable = $field{'C'};
$currkey = &xd($field{'I'});
$password = &xd($field{'P'});
$mode = lc($field{'M'});
$currpage = $field{'J'};
$exiturl = &xd($field{'U'});
if ( ($currkey) and (! $currtable) ) { $currtable = $TABLE_DEFAULT; $mode = 'e'; }
if ($currkey) {
  if ($currkey !~ /[a-z]/) {
    if ($COLS_KEYS{$currtable} !~ /\,/) {
      $currkey = $COLS_KEYS{$currtable}.'="'.$currkey.'"';
    }
  }
}
if ( ($mode eq 's') and ($field{'SUBMIT'} eq "COPY") ) {
  $mode = 'a'; $currkey = "";
}
if ($exiturl eq '') {
  $exiturlarg = '';
  $exiturlfield = "<input type=hidden name='u' value=''>";
  $exiturlhref = '';
} else {
  $exiturlarg = '&u='.&xe($exiturl);
  $exiturlfield  = "<input type=hidden name='u' value=".&xe($exiturl).">";
  if ($exiturl !~ /\//) {
    $exiturlhref = '/'.$exiturl;
  } else {
    $exiturlhref = $exiturl;
  }
}
$currpage =~ s/[^0-9]//g;
if ($currpage eq '') {
  $currpage = 0;
  $pagearg = '';
  $pagefield = "<input type=hidden name='j' value=''>";
} else {
  $pagearg = '&j='.$currpage;
  $pagefield = "<input type=hidden name='j' value=".$currpage.">";
}
$currsearch_onfield = $field{'W'};
$currsearch = lc(&xd($field{'S'}));
$searchmode = 'a';
if ($currsearch =~ / or /i) { $searchmode = 'o' }
while ($currsearch =~ / or /) { $currsearch =~ s/ or / /g }
while ($currsearch =~ / and /) { $currsearch =~ s/ and / /g }
while ($currsearch =~ /  /) { $currsearch =~ s/  / /g }
while ($currsearch =~ /^ /) { $currsearch =~ s/^ //g }
while ($currsearch =~ / $/) { $currsearch =~ s/ $//g }
$currsearch_show = $currsearch;
if ($currsearch eq '') {
  $searchtgt_arg = '';
  $searchtgt_field = '';
  $searchmode = '';
} else {
  if ($searchmode eq 'a') {
    while ($currsearch_show =~ / /) { $currsearch_show =~ s/ /\\\+/g }
  }
  if ($searchmode eq 'o') {
    while ($currsearch_show =~ / /) { $currsearch_show =~ s/ /\\\-/g }
  }
  while ($currsearch_show =~ /\\\+/) { $currsearch_show =~ s/\\\+/ and /g }
  while ($currsearch_show =~ /\\\-/) { $currsearch_show =~ s/\\\-/ or /g }
  $searchtgt_arg = '&s='.&xe($currsearch_show).'&w='.&xe($currsearch_onfield);
  $searchtgt_field = "<input type=hidden name='s' value=".&xe($currsearch_show).">";
  $searchtgt_field .= "<input type=hidden name='w' value=".&xe($currsearch_onfield).">";
}
@currsearches = split(/ /, $currsearch);
$currorderarg = &xd($field{'Q'});
$currorder = $currorderarg;
$orderdesc = '';
if ($currorder) {
  if (substr($currorder,0,1) eq '-') {
    $currorder = substr($currorder,1,length($currorder)-1);
    $orderdesc = ' DESC'
  }
  $currordersql = $currorder.$orderdesc
} else {
  if ($COLS_KEYS{$currtable} ne '') {
    $currordersql = $COLS_KEYS{$currtable};
    $orderdesc = ' DESC'
  } else {
    $currordersql = ""
  }
}
if ($currorderarg eq '') {
  $orderarg = '';
  $orderfield = "<input type=hidden name='q' value=''>";
} else {
  $orderarg = '&q='.&xe($currorderarg);
  $orderfield = "<input type=hidden name='q' value=".&xe($currorderarg).">";
}
$viewmode = &xd($field{'O'});
if ($viewmode eq '') {
  $viewmodearg = '';
  $viewmodefield = "<input type=hidden name='o' value=''>";
} else {
  $viewmodearg = '&o='.&xe($viewmode);
  $viewmodefield = "<input type=hidden name='o' value=".&xe($viewmode).">";
}
# In advanced view mode, override to include all fields.
if ($viewmode eq 'a') {
  foreach $tablename (@TABLES) {
    $COLS_VIEW{$tablename} = '*';
    $COLS_EDIT{$tablename} = '*';
  }
}
# Filter is continuously passed through, not entered from form or selector,
# assumed to be passed in from external link.
# Effects browse only, and only for a single table.
$currfilter_raw = &xd($field{'F'});
$cuttfilter_table = '';
if (substr($currfilter_raw,0,10) =~ /\./) {
  @currfilter_parts = split(/\./, $currfilter_raw);
  if ( ($currfilter_parts[0]) and ($currfilter_parts[1]) ) {
    $currfilter_table = $currfilter_parts[0];
    $currfilter = $currfilter_parts[1];
  }
}
if (! $currfilter_table) {
  $currfilter_table = $currtable;
  $currfilter = $currfilter_raw;
}
if (! $currfilter) {
  $filterarg = '';
  $filterfield = "<input type=hidden name='f' value=''>";
} else {
  $currfilter_out = '';
  if ($currfilter_table) { $currfilter_out .= $currfilter_table.'.'; }
  $currfilter_out .= $currfilter;
  $filterarg = '&f='.&xe($currfilter_out);
  $filterfield = "<input type=hidden name='f' value=".&xe($currfilter_out).">";
}

if (! $password) { $password = &GetPasswordCookie(); }
$password = $DB_PASSWORD;

if ($mode eq '') { $mode = 'b' }
if (! defined($mode_names{$mode})) {
  $mode_name = uc($mode)
} else {
  $mode_name = $mode_names{$mode}
}
if ( ("$DB_PASSWORD" eq '') or ("$DB_PASSWORD" ne "$password") ) {
  &DoLogin()
}
if ($mode eq 'e') { &DoEdit("") }
if ($mode eq 's') { &DoSave() }
if ($mode eq 'n') { &DoNew() }
if ($mode eq 'a') { &DoAdd() }
if ($mode eq 'c') { &DoDeleteConfirm() }
if ($mode eq 'd') { &DoDelete() }
print &HTML_Head('Browse');
DoBrowse();
exit;


##########################################
# MAJOR MODE HANDLERS

# Browse records.
sub DoBrowse {
  $in_browse = 1;
  if (! $currtable) {
    print "<font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font>";
    if ($exiturl) {
      print "<font size=2 color=black face=Arial>&nbsp;&nbsp;&nbsp;<a href='".$exiturlhref."'>EXIT</a></font>";
    }
    print "<br><br>\n";
    print "<font size=3>Select a table: ";
    foreach $tablename (@TABLES) {
      print '&nbsp;<a href="dbed.pl?c='.$tablename.$exiturlarg.$viewmodearg.$filterarg.'"><b>';
      $show_tablename = $tablename;
      $show_tablename = uc(substr($show_tablename,0,1)).lc(substr($show_tablename,1,length($show_tablename)-1));
      print $show_tablename.'</b></a>&nbsp;'
    }
    print "</font>\n";
    print "<br><br><br>\n".'<font size=2><a href="dbed.pl?'.$exiturlarg.'&o=';
    if ($viewmode ne 'a') {
      print 'a">Change to advanced';
    } else {
      print '">Return to normal';
    }
    print "</a> field set mode.<br>\n";
  } else {
    print "<a name='top'></a>";
    print "<table width='100%' border=0><tr>";
    print "<td valign=top align=left><font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font>";
    if ($exiturl) {
      print "<font size=2 color=black face=Arial>&nbsp;&nbsp;&nbsp;<a href='".$exiturlhref."'>EXIT</a></font>";
    }
    print "</td>";
    print "<form name='dbedbrowse' action='dbed.pl' method='post'>";
    print "<td align=center valign=top><font face=Arial size=2 color=black>";
    print "<a href='dbed.pl?c=$currtable' title='Start a search.'>Search</a>:&nbsp;";
    print $pagefield;
    print $orderfield;
    print $viewmodefield;
    print $filterfield;
    print $exiturlfield;
    print "<input type=hidden name='c' value='".$currtable."'>";
    print "<select name='w'>";
    @search_cols = split(/,/, $COLS_VIEW{$currtable});
    foreach $search_col (@search_cols) {
      print '<option value="'.$search_col.'"';
      if ( (! $currsearch_onfield) or ($currsearch_onfield eq $search_col) ) { print " selected"; }
      print '>'.$search_col."\n";
      if (! $currsearch_onfield) { $currsearch_onfield = $search_col; }
    }
    print "</select>";
	$currsearch_show = '*';
    print "<input type=text size=20 name='s' value='".$currsearch_show."'>";
    print "&nbsp;&nbsp;<input type=submit value='REFRESH'>";
    print "&nbsp;&nbsp;&nbsp;<a href='#bottom' title='BOTTOM'><font size=1>V</font></a>";
    print "</form>";
    print "</font></td>";
    print "<td align=right valign=top><font face=Arial size=2 color=black>";
    print "<a href=\"dbed.pl?".$exiturlarg."\" title=\"Change table.\">";
    $show_tablename = $currtable;
    $show_tablename = uc(substr($show_tablename,0,1)).lc(substr($show_tablename,1,length($show_tablename)-1));
    print '<b>'.$show_tablename."</b></a>&nbsp;&nbsp;&nbsp;&nbsp;";
    print "<a href=\"dbed.pl?m=n&c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg\" title='Create a new record.'>add</a>&nbsp;";
    print "</font></td></tr></table>";
    # Only browse if some search.
    if ($currsearch) {
      $b_db = DBI->connect($DB_INIT,$DB_LOGIN,$DB_PASSWORD);
      if (! $b_db) { &errexit("The database is not available."); }
      $select = $COLS_VIEW{$currtable};
      if(!$select){$select="*";};
      $curr_sql = "SELECT ".$select." FROM ".$currtable;
      $curr_sql_where = "";
      if ($currfilter) {
        if ($curr_sql_where) { $curr_sql_where .= " AND "; }
        $curr_sql_where .= $currfilter;
      }
      if ( ($currsearch) and ($currsearch !~ /[\'\"\ ]/) ) {
        if ($currsearch eq '*') {
          if ($curr_sql_where) { $curr_sql_where .= " AND "; }
          $curr_sql_where .= $currsearch_onfield.'<>""';
        } else {
          if ($curr_sql_where) { $curr_sql_where .= " AND "; }
          $curr_sql_where .= $currsearch_onfield.' LIKE "%'.$currsearch.'%"';
        }
      }
      if ($currsearch eq '*') { $currsearch = ''; }
      if ($curr_sql_where) { $curr_sql .= " WHERE ".$curr_sql_where; }
      if ($currordersql) {
        $curr_sql .= " ORDER BY ".$currordersql;
      }
      &WriteSQLLog();
      $sth=$b_db->prepare($curr_sql);
      $sth->execute or &errexit($b_db->errstr);
      $fieldcnt=$sth->{NUM_OF_FIELDS};
      @fieldnames = @{$sth->{NAME}};
      $tabletop = '';
      $tabletop .= "<table border='1' width='100%'><tr>";
      $tabletop .= "<td bgcolor='#eeeeee' width='20'>$tds &nbsp; $tde</td>";
      for ($fldlp=0;$fldlp<$fieldcnt;$fldlp++) {
        $tabletop .= "<td bgcolor='#eeeeee'>$tds&nbsp;<b><a href='dbed.pl?c=$currtable$searchtgt_arg$pagearg$exiturlarg";
        if (lc($currorder) eq lc($fieldnames[$fldlp])) {
          $tabletop .= "&q=";
          if ($orderdesc eq '') { $tabletop .= '-' }
          $tabletop .= &xe($fieldnames[$fldlp])."' title='Reverse sort order.'";
        } else {
          $tabletop .= "&q=$fieldnames[$fldlp]' title='Change sort field.'";
        }
        $fieldname_show = $fieldnames[$fldlp];
        $fieldname_show =~ s/^$currtable//i;
        $tabletop .= ">".$fieldname_show."</a></b>$tde</td>\n";
      }
      $totalrecs = 0;
      $validrecs = 0;
      while ( (@browserec=$sth->fetchrow_array) && ($validrecs <= ($MAX_RECS_PERPAGE*$MAX_PAGES)) ) {
        $totalrecs++;
        $currkey = "";
        $recsearch = '';
        $row_out = '';
        for ($fldlp=0;$fldlp<$fieldcnt;$fldlp++) {
          $browserec[$fldlp] = &stripslashes($browserec[$fldlp]);
          $recsearch .= ' '.lc($browserec[$fldlp]);
          if ( ($COLS_KEYS{$currtable} eq '') or ($COLS_KEYS{$currtable} =~ /$fieldnames[$fldlp]/i) ) {
            $currkey_val = $browserec[$fldlp];
            if ($currkey ne '') { $currkey .= " and " }
            $currkey .= $fieldnames[$fldlp].'="'.$currkey_val.'"';
          }
          $row_out .= "<td valign='top'>$tds&nbsp;";
          if ($fieldnames[$fldlp] =~ /address/i) {
            $row_out .= '<a href="http://maps.google.com?q='.&xe($browserec[$fldlp]).'" target="map">'.$browserec[$fldlp].'</a>';
          } else {
            if ($fieldnames[$fldlp] =~ /email/i) {
              $row_out .= '<a href="mailto:'.$browserec[$fldlp].'">'.$browserec[$fldlp].'</a>';
            } else {
              if ( ($fieldnames[$fldlp] =~ /url/) || ($fieldnames[$fldlp] =~ /web/) || ($browserec[$fldlp] =~ /http/) ) {
                $row_out .= '<a href="'.$browserec[$fldlp].'" target=_blank>'.$browserec[$fldlp].'</a>';
              } else {
                $row_out .= &xe(substr($browserec[$fldlp],0,200));
                if (length($browserec[$fldlp])>200) { $row_out .= '...'; }
              }
            }
          }
          $row_out .= $tde."</td>\n";
        }
        if ($recsearch ne '') { $recsearch .= ' ' }
        $validrec = 0;
        if ($currsearch eq '') {
          $validrec = 1
        } else {
          if ($searchmode eq 'o') { $validrec = 0 } else { $validrec = 1 }
          foreach $one_search (@currsearches) {
            while ($one_search =~ /\_/) { $one_search =~ s/\_/ /g }
            if ($searchmode eq 'o') {
              if ($recsearch =~ /$one_search/) {
                $validrec = 1;
                last;
              }
            } else {
              if ($recsearch !~ /$one_search/) {
                $validrec = 0;
                last;
              }
            }
          }
        }
        if ($validrec > 0) {
          $currkey = &xe($currkey);
          $rec_row_out[$validrecs] = "<tr>\n";
          $rec_row_out[$validrecs] .= '<td valign="top">'.$tds.'<a href="dbed.pl?m=e&i='.$currkey.'&c='.$currtable.$searchtgt_arg.$orderarg.$viewmodearg.$filterarg.$pagearg.$exiturlarg.'" title="Edit this record.">ed</a>&nbsp;';
          $rec_row_out[$validrecs] .= '<a href="dbed.pl?m='.$CONFIRM_DELETE.'&i='.$currkey.'&c='.$currtable.$searchtgt_arg.$orderarg.$viewmodearg.$filterarg.$pagearg.$exiturlarg.'" title="Delete this record.">x</a>'.$tde."</td>\n";
          $rec_row_out[$validrecs] .= $row_out;
          $rec_row_out[$validrecs] .= "</tr>\n\n";
          $validrecs++;
        }
      }
      print '<table cellspacing=0 cellpadding=0 border=0><tr>';
      print '<td valign=bottom><font size=2 face=Arial color=black>';
      $start_rec = $currpage * $MAX_RECS_PERPAGE;
      $end_rec = $start_rec + ($MAX_RECS_PERPAGE - 1);
      if ($end_rec > ($validrecs - 1)) { $end_rec = $validrecs - 1 }
      if ($start_rec > $end_rec) { $start_rec = $end_rec - ($MAX_RECS_PERPAGE - 1) }
      if ($start_rec < 0) { $start_rec = 0 }
      if ($currsearch) {
        if ($validrecs != $totalrecs) { print $validrecs." out of "; }
        print $totalrecs." match search."
      } else {
        print $totalrecs." total records."
      }
      if ($validrecs >= $MAX_RECS_PERPAGE) {
        print " &nbsp;&nbsp;&nbsp;Showing records ".($start_rec+1)." through ".($end_rec+1).'.'
      }
      print "</td><td> &nbsp;&nbsp;&nbsp;&nbsp; </td>";
      print '<form name="JUMPMENU" method=get align=top>';
      print '<td align=left valign=top><font face=Arial size=2 color=black>';
      print "Page: <select name=\"JUMPTO\" onChange=\"if (document.JUMPMENU.JUMPTO.options[document.JUMPMENU.JUMPTO.selectedIndex].value) { window.location = \'dbed.pl?c=".$currtable.$searchtgt_arg.$orderarg.$viewmodearg.$filterarg.$exiturlarg."&j=\'+document.JUMPMENU.JUMPTO.options[document.JUMPMENU.JUMPTO.selectedIndex].value }\">";
      for ($pgloop = 0; $pgloop <= ($totalrecs / $MAX_RECS_PERPAGE); $pgloop++ ) {
        print '<option value="'.$pgloop.'"';
        if ($pgloop == $currpage) { print ' selected' }
        print '>'.($pgloop+1).'</option>'
      }
      print '</select>';
      print '</td></form></tr></table>';
      if ($validrecs < 1) {
        print "<br>No records found.<br>"
      } else {
        print $tabletop;
        for ($rec_loop = $start_rec; $rec_loop <= $end_rec; $rec_loop++ ) {
          print $rec_row_out[$rec_loop];
        }
        print "</table>\n";
        print "<a name='bottom'></a><br><a href='#top' title='TOP'><font size=2>TOP</font></a><br>";
      }
      if($sth){$sth->finish;}
      $b_db->disconnect;
    }
  }
  if ($currtable eq $currfilter_table) {
    if ($currfilter) {
      print "<font size=1 color='".$color_dim."'><br>Filter in effect: ".&xe($currfilter)."<br>\n";
    }
  }
  print &HTML_Foot();
  &WriteMainLog("Showing ".$validrecs." out of ".$totalrecs);
  exit;
}

# Display form for edit record.
sub DoEdit {
  $edit_message = $_[0];
  if ($edit_message) {
      $edit_message = "&nbsp;&nbsp;<font color=red>".$edit_message."</font>";
  }
  print &HTML_Head('Edit');
  if ( ($currtable) and ($currkey) ) {
    $b_db = DBI->connect($DB_INIT,$DB_LOGIN,$DB_PASSWORD);
    $select = $COLS_EDIT{$currtable};
    if(!$select){$select="*";};
    $curr_sql = "SELECT ".$select." FROM ".$currtable;
    &WriteSQLLog();
    $sth = $b_db->prepare($curr_sql);
    $sth->execute or &errexit($b_db->errstr);
    $fieldcnt=$sth->{NUM_OF_FIELDS};
    @fieldnames = @{$sth->{NAME}};
    @fieldtype = @{$sth->{TYPE}};
    @nullable = @{$sth->{NULLABLE}};
    $sth->finish;
    $curr_sql = "SELECT ".$select." FROM ".$currtable." WHERE ".$currkey;
    &WriteSQLLog();
    $sth=$b_db->prepare($curr_sql) or &errexit($b_db->errstr);
    $sth->execute or &errexit($b_db->errstr);
    @editrec=$sth->fetchrow_array;
    $currkey=&xe($currkey);
    print "<font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font> - Edit ";
    $show_tablename = $currtable;
    $show_tablename = uc(substr($show_tablename,0,1)).lc(substr($show_tablename,1,length($show_tablename)-1));
    print $show_tablename." Record";
    $alt_links = '';
    foreach $alt_table (keys(%COLS_KEYS)) {
      if ($alt_table ne $currtable) {
        if ($COLS_KEYS{$alt_table} eq $COLS_KEYS{$currtable}) {
          $alt_links .= '&nbsp;<a href="dbed.pl?m=e&i='.$currkey.'&c='.$alt_table.$searchtgt_arg.$orderarg.$viewmodearg.$filterarg.$pagearg.$exiturlarg.'" title="Switch to '.$alt_table.'">'.$alt_table.'</a>';
        }
      }
    }
    if ($alt_links) { print "<font size=1>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Switch&nbsp;to:".$alt_links."</font>" }
    if ($exiturl) { print "<font size=1>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href='".$exiturlhref."'>EXIT</a></font>" }
    print "\n";
    if ($sth->rows < 1) {
      &errexitraw("<br>No record found matching key.")
    }
    if ($sth->rows > 1) {
      &errexitraw("<br>More than one record found matching key.")
    }
    print qq(<form name="EDITFORM" action="dbed.pl" method="post">
    <input type=hidden name="m" value="s">
    $searchtgt_field
    $pagefield
    $orderfield
    $viewmodefield
    $filterfield
    $exiturlfield
    <input type=hidden name="c" value="$currtable">
    <input type=hidden name="i" value="$currkey">
    );
    $rec_updated_shown = '';
    for ($fldlp=0;$fldlp<$fieldcnt;$fldlp++) {
      if ( ($fieldnames[$fldlp] =~ /recupdated/i) or ($fieldnames[$fldlp] =~ /dateupdated/i) ) {
        if ($editrec[$fldlp] =~ /[1-9]+/) {
          $rec_updated_shown = $editrec[$fldlp];
        }
      }
    }
    print qq(<table border="1"><tr><td bgcolor="#ddddff" align=left>$tds<input type=submit name="SUBMIT" value="SAVE">$edit_message$tde</td>);
    print '<td bgcolor="#ddddff" align=right>'.$tds;
    print '<b>'.$TABLE_NAME{$currtable}.'</b>';
    print ' &nbsp;&nbsp;<font size=1><i>'.$rec_updated_shown.'</i></font>';
    print qq( &nbsp;&nbsp;&nbsp;&nbsp;<a href="dbed.pl?m=$CONFIRM_DELETE\&i=$currkey\&c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg" title="Delete this record.">DELETE</a>&nbsp;&nbsp;&nbsp;<a href="dbed.pl?c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg" title="Return to browse.">BROWSE</a>&nbsp;$tde</td></tr>);
    for ($fldlp=0;$fldlp<$fieldcnt;$fldlp++) {
      if($nullable[$fldlp]){$nulla="null"}else{$nulla="not null"};
      $fieldname_shown = $fieldnames[$fldlp];
      $fieldname_shown =~ s/^$TABLE_PREFIX{$currtable}//;
      $fieldname_shown =~ s/^_//;
      print "<tr bgcolor='#eeeeee'><td align=right>$tds<b>";
      if ($fieldnames[$fldlp] =~ /address/i) {
        print '<a href="http://maps.google.com?q='.&xe($editrec[$fldlp]).'" target="map">'.$fieldname_shown.'</a>';
      } else {
        if ($fieldnames[$fldlp] =~ /email/i) {
          print '<a href="mailto:'.$editrec[$fldlp].'">'.$fieldname_shown.'</a>';
        } else {
          if ( ($fieldnames[$fldlp] =~ /url/) || ($fieldnames[$fldlp] =~ /web/) || ($browserec[$fldlp] =~ /http/) ) {
            print '<a href="'.$editrec[$fldlp].'" target=_blank>'.$fieldname_shown.'</a>';
          } else {
            print $fieldname_shown;
          }
        }
      }
      print "</b>$tde</td>\n";
      $editrec[$fldlp] = &stripslashes($editrec[$fldlp]);
      if (($TYPES{$fieldtype[$fldlp]}=~/long/) or ($TYPES{$fieldtype[$fldlp]}=~/bin/) and (!$select)) {
        $editfield = '<textarea cols="70" rows="'.((length($editrec[$fldlp])/60)+4).'" name="'.$fieldnames[$fldlp].'">'.&xe($editrec[$fldlp])."</textarea>\n";
      } else {
        $readonly = '';
        if ($COLS_READONLY{$currtable} =~ /$fieldnames[$fldlp]/i) {
		  $readonly = ' readonly';
        }
        $editfield = '<input type=text size="80" name="'.$fieldnames[$fldlp].'" value="'.&addquoteslashes($editrec[$fldlp]).'"'.$readonly.'>'."\n";
      }
      print '<td align=left>'.$tds.'&nbsp;'.$editfield.$tde.'</td></tr>'."\n";
    }
    print qq(
    <tr><td align=left bgcolor="#ddddff">$tds<input type=submit name="SUBMIT" value="SAVE">$tde</td>
    <td align=right bgcolor="#ddddff">$tds
    <input type=submit name="SUBMIT" value="COPY">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
    <a href="dbed.pl?m=$CONFIRM_DELETE&i=$currkey\&c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg" title="Delete this record.">DELETE</a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="dbed.pl?c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg" title="Return to browse.">BROWSE</a>&nbsp;$tde</td></tr>
    );
    print qq(
    </table>
    </form>
    );
    $sth->finish;
    $b_db->disconnect;
    print &HTML_Foot();
  } else {
    &errexit("Missing table or key.");
  }
  &WriteMainLog();
  exit;
}

# Save updated record.
sub DoSave {
  if ( ($currtable) and ($currkey) ) {
    $b_db = DBI->connect($DB_INIT,$DB_LOGIN,$DB_PASSWORD);
    $select = $COLS_EDIT{$currtable};
    if(!$select){$select="*";};
    $curr_sql = "SELECT ".$select." FROM ".$currtable." WHERE ".$currkey;
    &WriteSQLLog();+
    $sth=$b_db->prepare($curr_sql);
    $sth->execute or &errexit($b_db->errstr);
    @fieldnames = @{$sth->{NAME}};
    @fieldtype = @{$sth->{TYPE}};
    @nullable = @{$sth->{NULLABLE}};
    @origrec=$sth->fetchrow_array;
    $sth->finish;
    $anychange = 0;
    $fldnum_idx = 0;
    $curr_sql = "UPDATE ".$currtable." SET ";
    foreach $fieldname (@fieldnames) {
      if ( ($COLS_EDIT{$currtable} == '*') or ($COLS_EDIT{$currtable} == '')
           or ($COLS_EDIT{$currtable} =~ /$fieldname/i) ) {
        # Save only writable fields.
        if ($COLS_READONLY{$currtable} !~ /$fieldname/i) {
          $field_val = addslashes(&xd($field{uc($fieldname)}));
          # Save only changed fields.
          if ($field_val ne stripslashes($origrec[$fldnum_idx])) {
            if ($TYPES{$fieldtype[$fldnum_idx]} =~ /date/i) {
              if ($field_val) {
                $curr_sql .= $fieldname.'="'.$field_val.'",';
              } else {
                $curr_sql .= $fieldname.'="0000-00-00",';
              }
            } else {
              if ($numeric_types =~ /$TYPES{$fieldtype[$fldnum_idx]}/i) {
                if ($field_val) {
                  $curr_sql .= $fieldname.'='.$field_val.',';
                } else {
                  $curr_sql .= $fieldname.'=0,';
                }
              } else {
                $curr_sql .= $fieldname.'="'.$field_val.'",';
              }
            }
            $anychange++;
          }
        }
      }
      $fldnum_idx++;
    }
    $curr_sql = substr($curr_sql,0,length($curr_sql)-1);
    $curr_sql .= " WHERE ".$currkey;
    if ($anychange > 0) {
      &WriteSQLLog();
      $b_db->do($curr_sql) or &errexit($b_db->errstr);
      $b_db->disconnect;
      &DoEdit("Saved");
    } else {
      &DoEdit("Same");
    }
  } else {
    print &HTML_Head('Save');
    &errexit("Missing table or key.");
  }
  exit;
}

# Display form for new record.
sub DoNew {
  print &HTML_Head('Add');
  if ($currtable) {
    $b_db = DBI->connect($DB_INIT,$DB_LOGIN,$DB_PASSWORD);
    $select = $COLS_EDIT{$currtable};
    if(!$select){$select="*";};
    $curr_sql = "SELECT ".$select." FROM ".$currtable;
    &WriteSQLLog();
    $sth = $b_db->prepare($curr_sql);
    $sth->execute or &errexit($b_db->errstr);
    $fieldcnt=$sth->{NUM_OF_FIELDS};
    @fieldnames = @{$sth->{NAME}};
    @fieldtype = @{$sth->{TYPE}};
    @nullable = @{$sth->{NULLABLE}};
    $sth->finish;
    print "<font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font> - Add ";
    $show_tablename = $currtable;
    $show_tablename = uc(substr($show_tablename,0,1)).lc(substr($show_tablename,1,length($show_tablename)-1));
    print $show_tablename." Record";
    print qq(<form action="dbed.pl" method="post">
    <input type=hidden name="m" value="a">
    $searchtgt_field
    $pagefield
    $orderfield
    $viewmodefield
    $filterfield
    $exiturlfield
    <input type=hidden name="c" value="$currtable">
    );
    print qq(<table border="1"><tr><td bgcolor="#ddddff" align=left>$tds<input type=submit name="SUBMIT" value="SAVE">$tde</td>);
    print '<td bgcolor="#ddddff" align=right>'.$tds;
    print '&nbsp;&nbsp;<b>'.$TABLE_NAME{$currtable}.'</b>';
    print qq( &nbsp;&nbsp;<a href="dbed.pl?c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg" title="Return to browse.">BROWSE</a>&nbsp;$tde</td></tr>);
    for ($fldlp=0;$fldlp<$fieldcnt;$fldlp++) {
      if ($COLS_READONLY{$currtable} !~ /$fieldnames[$fldlp]/i) {
		if($nullable[$fldlp]){$nulla="null"}else{$nulla="not null"};
        $fieldname_shown = $fieldnames[$fldlp];
        $fieldname_shown =~ s/^$TABLE_PREFIX{$currtable}//;
        $fieldname_shown =~ s/^_//;
        print "<tr bgcolor='#eeeeee'><td align=right>".$tds."<b>".$fieldname_shown."</b>".$tde."</td>\n";
        print "<!-- ".$TYPES{$fieldtype[$fldlp]}." -->";
        if (($TYPES{$fieldtype[$fldlp]}=~/long/) or ($TYPES{$fieldtype[$fldlp]}=~/bin/) and (!$select)) {
          $editfield=qq(<textarea cols="70" rows="4" name="$fieldnames[$fldlp]"></textarea>\n);
        } else {
          $editfield=qq(<input type=text size="80" name="$fieldnames[$fldlp]" value="">\n);
        }
        print qq(<td align=left>$tds&nbsp;$editfield$tde</td></tr>\n);
      }
    }
    print qq(
    <tr><td align=left bgcolor="#ddddff">$tds<input type=submit name="SUBMIT" value="SAVE">$tde</td>
    <td align=right bgcolor="#ddddff">$tds<a href="dbed.pl?c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg" title="Return to browse.">BROWSE</a>&nbsp;$tde</td></tr>
    );
    print qq(
    </table>
    </form>
    );
    $sth->finish;
    $b_db->disconnect;
    print &HTML_Foot();
  } else {
    &errexit("Missing table.");
  }
  &WriteMainLog();
  exit;
}

# Save new record.
sub DoAdd {
  if ($currtable) {
    $b_db = DBI->connect($DB_INIT,$DB_LOGIN,$DB_PASSWORD);
    $select = $COLS_EDIT{$currtable};
    if(!$select){$select="*";};
    $curr_sql = "SELECT ".$select." FROM ".$currtable;
    &WriteSQLLog();
    $sth=$b_db->prepare($curr_sql);
    $sth->execute or &errexit($b_db->errstr);
    @fieldnames = @{$sth->{NAME}};
    @fieldtype = @{$sth->{TYPE}};
    @nullable = @{$sth->{NULLABLE}};
    @key_column_names = $b_db->primary_key( undef, undef, $currtable );
	if (defined(@key_column_names[0])) { $key_column = $key_column_names[0]; }
    $sth->finish;
    $curr_sql = "INSERT INTO ".$currtable." SET ";
    $fldnum_idx = 0;
    $anychange = 0;
    $currkey = "";
	foreach $fieldname (@fieldnames) {
      if ( ($COLS_EDIT{$currtable} eq '*') or ($COLS_EDIT{$currtable} eq '') or ($COLS_EDIT{$currtable} =~ /$fieldname/i) ) {
        $field_val = addslashes(&xd($field{uc($fieldname)}));
		$curr_sql_part = "";
        # Save only writable fields.
        if ( ($TYPES{$fieldtype[$fldnum_idx]} =~ /date/i) or
             ($TYPES{$fieldtype[$fldnum_idx]} =~ /time/i) ) {
          if ($field_val) {
            $curr_sql_part .= $fieldname.'="'.$field_val.'",';
          } else {
            $curr_sql_part .= $fieldname.'="0000-00-00 00:00",';
          }
        } else {
          if ($numeric_types =~ /$TYPES{$fieldtype[$fldnum_idx]}/i) {
            if ($field_val) {
              $curr_sql_part .= $fieldname.'='.$field_val.',';
            } else {
              $curr_sql_part .= $fieldname.'=0,';
            }
          } else {
            $curr_sql_part .= $fieldname.'="'.$field_val.'",';
          }
        }
        if ($COLS_READONLY{$currtable} !~ /$fieldname/i) {
		  $curr_sql .= $curr_sql_part;
          $anychange++;
        }
		if ($key_column) { $currkey = $key_column; }
	  }
      $fldnum_idx++;
    }
    $curr_sql = substr($curr_sql,0,length($curr_sql)-1);
    &WriteSQLLog();
    $b_db->do($curr_sql) or &errexit($b_db->errstr);
    $currkey .= '='.$b_db->{mysql_insertid};
	print &HTML_Head('Added');
    print "<b>New record saved.&nbsp;&nbsp;";
    print "<a href=\"dbed.pl?m=e&i=$currkey&c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg\" title=\"Edit.\">EDIT</a>";
    print "<br><br>\n";
    &WriteMainLog();
    print "<a href=\"dbed.pl?c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg\" title=\"Return to browse.\">RETURN TO BROWSE</a>\n";
    print &HTML_Foot();
    $b_db->disconnect;
    exit;
  } else {
    print &HTML_Head('Add');
    &errexit("Missing table.");
  }
}

# Confirm delete of specified record.
sub DoDeleteConfirm {
  print &HTML_Head('Delete Confirm');
  print "<font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font> - Delete Record<br>\n";
  if ( ($currtable) and ($currkey) ) {
    print "<br><font size=2>Record key: ".$currtable.' '.$currkey."<br><br></font>\n";
    $b_db = DBI->connect($DB_INIT,$DB_LOGIN,$DB_PASSWORD);
    $curr_sql = "SELECT ".$COLS_EDIT{$currtable}." FROM ".$currtable." WHERE ".$currkey;
    &WriteSQLLog();
    $dbs = $b_db->prepare($curr_sql) or &errexit($b_db->errstr);
    $dbs->execute;
    $db_err = $b_db->errstr; if ($db_err ne '') { &errexitraw($b_db->errstr) }
    @db_cols = $dbs->fetchrow_array;
    $db_err = $b_db->errstr; if ($db_err ne '') { &errexitraw($b_db->errstr) }
    if ($dbs->rows != 1) { &errexitraw("Key does not select a single record.") }
    $dbs->finish;
    $b_db->disconnect;
    $currkey = &xe($currkey);
    print "<a href=\"dbed.pl?m=d&i=$currkey&c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg\">DELETE</a> &nbsp;&nbsp;&nbsp;";
    print "<a href=\"dbed.pl?c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg\" title=\"Return to browse.\">BROWSE</a> &nbsp;&nbsp;&nbsp;\n";
    print "<a href=\"dbed.pl?m=e&i=$currkey&c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg\" title=\"Edit.\">EDIT</a>\n";
    print &HTML_Foot();
    &WriteMainLog();
    exit;
  } else {
    &errexit("Missing table or key.")
  }
}

# Delete specified record.
sub DoDelete {
  print &HTML_Head('Deleted');
  print "<font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font> - Record Deleted<br>\n";
  print "<br><font size=2>Record key: ".$currtable.' '.$currkey."<br><br></font>\n";
  if ($currkey and $currtable) {
    $b_db = DBI->connect($DB_INIT,$DB_LOGIN,$DB_PASSWORD);
    $curr_sql = "SELECT ".$COLS_EDIT{$currtable}." FROM ".$currtable." WHERE ".$currkey;
    &WriteSQLLog();
    $dbs = $b_db->prepare($curr_sql) or &errexit($b_db->errstr);
    $dbs->execute;
    $db_err = $b_db->errstr; if ($db_err ne '') { &errexitraw($b_db->errstr) }
    @db_cols = $dbs->fetchrow_array;
    $db_err = $b_db->errstr; if ($db_err ne '') { &errexitraw($b_db->errstr) }
    if ($dbs->rows != 1) { &errexitraw("Key does not select a single record.") }
    $dbs->finish;
    $curr_sql = "DELETE FROM ".$currtable." WHERE ".$currkey;
    &WriteSQLLog();
    $b_db->do($curr_sql) or &errexit($b_db->errstr);
    $b_db->disconnect;
  } else {
    &errexit("Missing table or key.")
  }
  &WriteMainLog();
  print "<a href=\"dbed.pl?c=$currtable$searchtgt_arg$orderarg$viewmodearg$filterarg$pagearg$exiturlarg\" title=\"Return to browse.\">BROWSE</a>\n";
  print &HTML_Foot();
  exit;
}

# Show login form and exit.
sub DoLogin {
  print "Content-type: text/html; charset=UTF-8\n\n".'<html><head><title>dbed '.$LOCAL_TITLE.' - Login</title></head><body bgcolor=white onLoad="document.loginform.p.focus()"><font face=Arial color=black size=2>'."\n";
  print "password was: ".$password." should be: ".$DB_PASSWORD."\n";
  print "<font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font><br>\n";
  print "<form action='dbed.pl' method='post' name='loginform'>\n";
  print "<input type=password name='p' size=20>\n";
  print $searchtgt_field;
  print $pagefield;
  print $orderfield;
  print $viewmodefield;
  print $filterfield;
  print $exiturlfield;
  print "<input type=hidden name='m' value='".$mode."'>\n";
  print "<input type=hidden name='c' value='".$currtable."'>\n";
  print "<input type=hidden name='i' value='".&xe($currkey)."'>\n";
  print "<input type=submit name='LOGIN' value='LOGIN'>\n";
  print "</form>\n";
  print &HTML_Foot();
  &WriteMainLog('LOGIN');
  exit;
}

# Show error message and exit.
sub errexitraw {
  $errmsg = $_[0];
  print "<font size=3 color=red><br>Error:</font> <b>$errmsg</b><br><br>\n";
  print "<a href='javascript:history.back();'>&lt;&lt;&lt;&nbsp;BACK</a>";
  print "<br><br><a href='dbed.pl?c=".$currtable.$searchtgt_arg.$orderarg.$viewmodearg.$filterarg.$pagearg.$exiturlarg."' title='Return to browse.'>BROWSE</a><br>\n";
  if ($exiturl) { print "<br><a href='".$exiturlhref."'>EXIT</a><br>" }
  print &HTML_Foot();
  &WriteMainLog('ERROR '.$errmsg);
  exit;
}

sub errexit {
  $errmsg = $_[0];
  print "<font face=Arial color=green size=3><b>Database&nbsp;Editor</b></font><br>\n";
  &errexitraw($errmsg);
}

########################################
# SUPPORTING ROUTINES

# Convert troublesome characters to HEX for passing and storing.
sub xe {  # heX Encode
  $safe_str= $_[0];
  $safe_out = '';
  for ($safe_lp = 0; $safe_lp < length($safe_str); $safe_lp++ ) {
    $safe_char = substr($safe_str,$safe_lp,1);
    if ( ($safe_char lt ' ') or ($safe_char gt 'z') or
         ($safe_char eq '%') or ($safe_char eq '~') or
         ($safe_char eq '+') or
         ($safe_char eq "\'") or ($safe_char eq '"') or
         ($safe_char eq '<') or ($safe_char eq '>') or
         ($safe_char eq '&') or ($safe_char eq '#') or
         ($safe_char eq '\\') or ($safe_char eq '/') or
         ($safe_char eq '?') or ($safe_char eq '@') ) {
      $safe_char = '%'.sprintf("%02x", ord($safe_char)) }
    $safe_out .= $safe_char;
  }
  return $safe_out;
}

sub xd {  # heX Decode
  $safe_str = $_[0];
  $safe_str =~ s/%(..)/pack("c",hex($1))/ge;
  $safe_str =~ s/\r//g;
  return $safe_str;
}

sub GetPasswordCookie {
  if ($password eq '') {
    @cookies = split(/;/, $ENV{'HTTP_COOKIE'});
    foreach $cookie_pair (@cookies) {
	  ($cookie_name, $cookie_value) = split(/=/, $cookie_pair);
      $cookie_name =~ s/ //g;
      if ($cookie_name eq 'dbedpw') { $password = &xd($cookie_value); }
    }
  }
}

sub stripslashes {
  $arg_in = $_[0];
  $arg_in =~ s/\\\\/\\/g;
  $arg_in =~ s/\\\'/\'/g;
  $arg_in =~ s/\\\"/\"/g;
  return($arg_in);
}

sub addslashes {
  $arg_in = $_[0];
  $arg_in = stripslashes($arg_in);
  $arg_in =~ s/\\/\\\\/g;
  $arg_in =~ s/\'/\\\'/g;
  $arg_in =~ s/\"/\\\"/g;
  return($arg_in);
}

sub addquoteslashes {
  $arg_in = $_[0];
  # $arg_in =~ s/\"/\%22/g;
  $arg_in = &xe($arg_in);
  return($arg_in);
}

sub HTML_Head {
  $head_title = $_[0];
  $set_cookie = "";
  if ($password ne '') {
    $set_cookie .= "<SCRIPT LANGUAGE=JAVASCRIPT TYPE=\"TEXT/JAVASCRIPT\">\n";
    $x_time = time + (24 * 60 * 60);
    @DayNames = ('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday');
    @MonthNames = ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');
    ($x_Sec, $x_Min, $x_Hr, $x_Da, $x_Mo, $x_Yr, $x_DOW) = gmtime($x_time);
    $x_Mo++;  $x_Yr += 1900;
    $x_date = sprintf("%s, %02d-%s-%04d %02d:%02d:%02d GMT",
                    substr($DayNames[$x_DOW],0,3),
                    $x_Da, substr($MonthNames[$x_Mo-1],0,3), $x_Yr,
                    $x_Hr, $x_Min, $x_Sec);
    $cookie_args = "; path=/; expires=".$x_date;
    $set_cookie .= "document.cookie = \"dbedpw=".&xe($password).$cookie_args."\"\n";
    $set_cookie .= "</SCRIPT>\n";
  }
  $head_out = "";
  $head_out .= "Content-type: text/html; charset=UTF-8\n\n";
  $head_out .= "<html><head><title>dbed ".$LOCAL_TITLE." - ".$head_title."</title>\n";
  $head_out .= $set_cookie;
  $head_out .= "</head>\n";
  $head_out .= "<body bgcolor=white><font face=Arial color=black size=2>\n";
  return($head_out);
}

sub HTML_Foot {
  return( "</font></body></html>\n" );
}

sub WriteMainLog {
  $LogMsg = $_[0];
  if (length($LogMsg) > 240) { $LogMsg = substr($LogMsg,0,240).'...'; }
  &TrackingLog($LogMsg);
}

sub WriteSQLLog {
  if ($writesqllog_bite > 0) {
    $LogMsg = $curr_sql;
    if (length($LogMsg) > $writesqllog_bite) { $LogMsg = substr($LogMsg,0,$writesqllog_bite).'...'; }
    &TrackingLog($LogMsg);
  }
}

sub TrackingLog {
  $log_in = $_[0];
  $log_in =~ s/[\r\n\f\t]+/ /gmi;
  ($LogSec, $LogMin, $LogHr, $LogDa, $LogMo, $LogYr) = localtime();
  $LogMo++;  $LogYr += 1900;
  $LogYYYYMMDDHHMMSS = sprintf("%04d.%02d.%02d %02d:%02d:%02d", $LogYr, $LogMo, $LogDa, $LogHr, $LogMin, $LogSec);
  open (TRACK_LOG, ">> dbed.log");
  if (TRACK_LOG) {
    print TRACK_LOG $LogYYYYMMDDHHMMSS." ".$log_in."\n";
    close (TRACK_LOG);
    chmod(0666, "dbed.log");
  }
}

# Collect environment.
sub GetFormInput {
  local ($buf);
  # Reads all get or post form values in ENV space.
  # Alternately takes -x= format command line argument equivalents.
  $buf = '';
  (*fval) = @_ if @_;
  if ($ENV{'REQUEST_METHOD'} eq 'POST') {
    read(STDIN,$buf,$ENV{'CONTENT_LENGTH'});
  } else {
    $buf=$ENV{'QUERY_STRING'};
  }
  if ($buf !~ /[a-zA-Z0-9]/) {
    for ($arg_lp = 0; $arg_lp < @ARGV; $arg_lp++) {
      if (substr($ARGV[$arg_lp],0,3) =~ /\-[a-z]\=/) {
        $buf .= '&'.substr($ARGV[$arg_lp],1,length($ARGV[$arg_lp])-1);
      }
    }
    if (! $buf) { $buf = $ARGV[0]; }
  }
  if ($buf eq "") {
    return 0;
  } else {
    @fval=split(/&/,$buf);
    foreach $i (0 .. $#fval) {
      ($name,$val)=split (/=/,$fval[$i],2);
      $val=~tr/+/ /;
      $val=~ s/%(..)/pack("c",hex($1))/ge;
      $name=~tr/+/ /;
      $name=~ s/%(..)/pack("c",hex($1))/ge;
      $name = uc($name);
      if (!defined($field{$name})) {
        $field{$name}=$val;
      } else {
        $field{$name} .= ",$val";
        #if you want multi-selects to goto into an array change to:
        #$field{$name} .= "\0$val";
      }
    }
  }
  return 1;
}
