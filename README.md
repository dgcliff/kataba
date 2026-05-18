# Kataba
[![Gem Version](https://badge.fury.io/rb/kataba.svg)](https://badge.fury.io/rb/kataba)

## Description
Kataba (片刃) provides XML Schema Definition (XSD) mirroring and offline validation for Nokogiri

## Features
* Configuration to enable optional mirror list for XSD files
* Configuration to alter offline storage location
* Recursive XSD search to ensure total depth processing (i.e. XSD -> import -> etc.)

## Design rationale: why a flat MD5-keyed cache?

The cache layout — every transitively-imported XSD stored as
`<md5(URL)>.xsd` in one flat directory, with each `schemaLocation`
attribute in the cached files rewritten to those MD5'd filenames — is a
deliberate workaround for two stacked constraints in the
Nokogiri / libxml / JRuby stack. Capturing the rationale here so the
gem's "weirdness" stays explained even if the upstream links rot.

**1. libxml resolves `xs:import schemaLocation` against the working
directory at schema-parse time.** If the schemaLocation is an absolute
URL, libxml goes off and fetches it over the network — slow, fragile,
and the reason this gem exists in the first place. The classic
workaround ([documented by Ktulu in 2011][ktulu]) is to put every
imported XSD in one directory, rewrite each import to a *relative*
filename, and `Dir.chdir` to that directory at schema-load time.
Kataba automates that recipe: `fetch_schema` wraps the
`Nokogiri::XML::Schema(...)` call in a `Dir.chdir(offline_storage)`
block.

**2. Under JRuby + nokogiri-java, `Dir.chdir` doesn't propagate to the
Java code that handles imports** ([reproduction repo][dougalcorn];
JRuby's lead maintainer has stated on JIRA that `Dir.chdir` is fragile
under JRuby and full paths should be preferred). The portable fix is to
remove path resolution from the picture entirely: store every cached
XSD as a flat sibling, and rewrite every `schemaLocation` to a bare
filename with no directory components. With nothing to resolve, neither
MRI's libxml nor nokogiri-java has anything to get wrong.

**MD5(URL) is the collision-free flat-name function.** In real-world
schemas, imports collide on basename — `http://www.loc.gov/mods/xml.xsd`
and `http://www.w3.org/2001/xml.xsd` both end in `xml.xsd`. Hashing the
full URL gives a stable, deterministic per-source filename without
inventing a path-flattening scheme. (MD5 here is a content-addressable
name, not a security primitive — collision resistance against random
URLs is more than enough.)

**`download_xsd` is recursive** because `xs:import` chains aren't always
one level deep: `mods-3-5.xsd` imports `xlink.xsd` and `xml.xsd`, and
other schemas chain further. After each fetch, every `schemaLocation`
in the file is captured and rewritten in place, then the loop runs
again on any new URIs that surfaced.

[ktulu]: https://web.archive.org/web/20130124234433/http://ktulu.com.ar/blog/2011/06/26/resolving-validation-errors-using-nokogiri-and-schemas/
[dougalcorn]: https://web.archive.org/web/20180611032704/https://github.com/dougalcorn/nokogiri-chdir-schema-validate-bug

## Installation
```
gem install kataba
```

## Usage

### Configuration (optional)
```Kataba.configuration.offline_storage = "/tmp/kataba"```

```Kataba.configuration.mirror_list = File.join(Rails.root, 'config', 'mirror.yml')```

### Download
The fetch_schema method returns a Nokogiri::XML::Schema object

```xsd = Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")```
