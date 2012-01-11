IPBoard to Wordpress Migration Script
=====================================

A simple ruby script which builds a Wordpress WXR XML file for importing a IPBoard into a Wordpress blog. Topics are broken down into posts and replies are inserted as comments within the post. Reply hierarchy is kept in the comments if available within the topic. BBCode is also converted to HTML.

How to use
----------

`bundle install`

`ruby script.rb -u database_username -h database_host -d database_name`