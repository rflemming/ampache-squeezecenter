## Overview ##
SqueezeCenter plugin which allows browsing and playing of music residing on a remote Ampache server.  This effectively allows for a remote SqueezeCenter catalog.

## News ##
### 03/07/2010 - Ampache Plugin v1.4 Released ###
  * Updated for Squeezecenter version 7.4.x - Moved plugin under Internet Radio menu since Music Services is no longer available.

### 07/11/2009 - Ampache Plugin v1.3 Released ###
  * Restructured how prefs are stored
  * Automatically reload plugin after configuration changes

### 06/28/2009 - Ampache Plugin v1.2 Released ###
  * Another non-included PERL module fix, which solves running under Windows issue.

### 06/25/2009 - Ampache Plugin v1.1 Released ###
  * Includes Digest::SHA::PurePerl
  * Fix metadata fetching for songs in the current playlist

### 06/24/2009 - Ampache 3.5.1 Release ###
This latest release resolves all known API issues with the current branch of [Ampache](http://www.ampache.org/).

## Installation ##
### Manual Installation ###
  * Remove any previous version of the plugin from the SqueezeCenter Plugins directory.
  * Download the latest version of the plugin from the [Downloads](http://code.google.com/p/ampache-squeezecenter/downloads/list) page.
  * Unzip the plugin into the Plugins directory.
  * Restart SqueezeCenter
  * Configure the plugin

### Using the Extension Downloader ###
  * Open up the Extension Downloader configuration in SqueezeCenter under Settings/Plugins/Extension Downloader/Settings
  * Add the repository:
> http://ampache-squeezecenter.googlecode.com/svn/tags/repo.xml
  * Select the plugin for installation
  * Restart SqueezeCenter
  * Configure the plugin

## Bugs and Known Issues ##
### Ampache 3.4 ###
There is a [bug](http://ampache.org/bugs/ticket/413) in the playlist generation code in all 3.4 versions of Ampache.  This bug generates invalid XML which the plugin isn't all too happy with.  You can fix this bug yourself by applying the patch below to your Ampache 3.4 source:

```
--- lib/class/xmldata.class.php 2008-12-26 04:09:57.000000000 -0800
+++ lib/class/xmldata.class.php 2009-05-23 16:49:27.000000000 -0700
@@ -244,7 +244,7 @@
      // Build this element
      $string .= "<playlist id=\"$playlist->id\">\n" .
        "\t<name><![CDATA[$playlist->name]]></name>\n" .
-       "\t<owner><![CDATA[$playlist->f_user]]</owner>\n" .
+       "\t<owner><![CDATA[$playlist->f_user]]></owner>\n" .
        "\t<items>$item_total</items>\n" .
        "\t<type>$playlist->type</type>\n" .
        "</playlist>\n";
```

## Donate ##
Donations to the cause graciously accepted via PayPal:
[![](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=48NRH82ZKVGBA&lc=US&item_name=Robert%20Flemming&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted)