# Kataba
[![Gem Version](https://badge.fury.io/rb/kataba.svg)](https://badge.fury.io/rb/kataba)

## Description
Kataba (片刃) provides XML Schema Definition (XSD) mirroring and offline validation for Nokogiri

## Features
* Configuration to enable optional mirror list for XSD files
* Configuration to alter offline storage location
* Recursive XSD search to ensure total depth processing (i.e. XSD -> import -> etc.)

## Restrictions
* All required XSD files are downloaded and renamed to the MD5 of their URI so they can be unique
* Flat folder structure - see http://ktulu.com.ar/blog/2011/06/26/resolving-validation-errors-using-nokogiri-and-schemas/

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
