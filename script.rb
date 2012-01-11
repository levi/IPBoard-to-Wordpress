#!/usr/bin/ruby

require "rubygems"
require "bundler/setup"

require 'choice'
require 'highline/import'
require 'mysql'
require 'nokogiri'
require 'bbcoder'

Choice.options do
  header 'Script options:'

  separator 'Required:'

  option :username, :required => true do
    short '-u'
    long '--username=USERNAME'
    desc 'The MySQL database username'
  end

  option :host, :required => true do
    short '-h'
    long '--host=HOST'
    desc 'The MySQL database host'
  end

  option :database, :required => true do
    short '-d'
    long '--database=DATABASE'
    desc 'The MySQL database name'
  end

  option :permalink_url, :required => true do
    short '-p'
    long '--permalink-url=http://example.com'
    desc 'The new blog\'s permalink url'
  end
end

password = ask("Password: ") { |q| q.echo = false }

# First get the required data from the sql server

posts = []

begin
  mysql = Mysql.real_connect(Choice.choices.host, Choice.choices.username, password, Choice.choices.database, 3306)

  res = mysql.query("SELECT `topics`.`tid` AS `post_id`,
                            `topics`.`title`,
                            FROM_UNIXTIME(`topics`.`start_date`, '%a, %d %b %Y %T +0000') AS `pubDate`,
                            FROM_UNIXTIME(`topics`.`start_date`, '%Y-%m-%d %T') AS `post_date`,
                            `topics`.`title_seo` AS `link`,
                            `posts`.`author_name` AS `creator`,
                            `posts`.`post` AS `content`,
                            `forums`.`name` AS `category_name`,
                            `forums`.`name_seo` AS `category_slug`
                       FROM `topics`, `posts`, `forums`
                      WHERE `posts`.`topic_id` = `topics`.`tid`
                        AND `topics`.`forum_id` = `forums`.`id`
                        AND `posts`.`new_topic` = 1
                        AND (`posts`.`author_name` = 'Doug Carlson'
                         OR `posts`.`author_name` = 'Russell Castagnaro'
                         OR `posts`.`author_name` = 'Kelli Miura')
                   ORDER BY `topics`.`start_date` ASC")

  res.each_hash do |row|
    hash = row
    hash["comments"] = []

    comments = mysql.query("SELECT `posts`.`pid` AS `comment_id`,
                            `posts`.`author_name` AS `comment_author`,
                            `members`.`email` AS `comment_author_email`,
                            `posts`.`ip_address` AS `comment_author_IP`,
                             FROM_UNIXTIME(`posts`.`post_date`, '%Y-%m-%d %T') AS `comment_date_gmt`,
                            `posts`.`post` AS `comment_content`,
                             CASE WHEN `posts`.`post_parent` <> 0 THEN `posts`.`post_parent` ELSE 0 END AS `comment_parent`
                       FROM `posts`, `members`
                      WHERE `posts`.`topic_id` = #{row['post_id']}
                        AND `posts`.`author_id` = `members`.`member_id`
                        AND `posts`.`new_topic` = 0
                   ORDER BY `posts`.`post_date` ASC")
    comments.each_hash do |comment|
      hash["comments"] << comment
    end
    posts << hash
  end
rescue Mysql::Error => e
  puts "Error code: #{e.errno}"
  puts "Error message: #{e.error}"
  puts "Error SQLSTATE: #{e.sqlstate}" if e.respond_to? "sqlstate"
ensure
  # close connection
  mysql.close if mysql
end

# build the xml, convert the BBCode to HTML

builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
  xml.rss("version" => "2.0",
          "xmlns:content" => "http://purl.org/rss/1.0/modules/content/",
          "xmlns:excerpt" => "http://wordpress.org/export/1.0/excerpt/",
          "xmlns:dsq" => "http://www.disqus.com/",
          "xmlns:dc" => "http://purl.org/dc/elements/1.1/",
          "xmlns:wp" => "http://wordpress.org/export/1.0/") {
    xml.channel {
      xml.language 'en'
      xml['wp'].wxr_version 1.0

      posts.each do |p|
        xml["wp"].category {
          xml["wp"].category_nicename p['category_slug']
          xml["wp"].category_parent
          xml["wp"].cat_name {
            xml.cdata p['category_name']
          }
        }
      end

      posts.each do |p|
        permalink = "#{Choice.choices.permalink_url}/#{p['category_slug']}/#{p['link']}"
        xml.item {
          xml.guid(:isPermalink => "false") {
            permalink
          }
          xml.title p['title']
          xml.link permalink
          xml.pubDate p['pubDate']
          xml['dc'].creator {
            xml.cdata p['creator']
          }

          xml.category { xml.cdata p['category_name'] }

          xml.category( :domain => "category", :nicename => p['category_slug'] ) {
            xml.cdata p['category_name']
          }

          xml['content'].encoded {
            xml.cdata p['content'].bbcode_to_html
          }
          xml['excerpt'].encoded
          xml['dsq'].thread_identifier permalink
          xml['wp'].post_id p['post_id']
          xml['wp'].post_date_gmt p['post_date']
          xml['wp'].ping_status 'closed'
          xml['wp'].status 'publish'
          xml['wp'].post_parent 0
          xml['wp'].menu_order 0
          xml['wp'].post_type 'post'
          xml['wp'].post_password
          xml['wp'].comment_status 'open'
          xml['wp'].is_sticky 0

          p['comments'].each do |c|
            xml['wp'].comment {
              xml['wp'].comment_id c['comment_id']
              xml['wp'].comment_author c['comment_author']
              xml['wp'].comment_author_email c['comment_author_email']
              xml['wp'].comment_author_url
              xml['wp'].comment_author_IP c['comment_author_IP']
              xml['wp'].comment_date_gmt c['comment_date_gmt']
              xml['wp'].comment_content {
                xml.cdata c['comment_content'].bbcode_to_html
              }
              xml['wp'].comment_approved 1
              xml['wp'].comment_type
              xml['wp'].comment_parent c['comment_parent']
              xml['wp'].comment_user_id 0
            }
          end
        }
      end
    }
  }
end

# save to file in the local directory
output_xml = File.new("ipboard_migration.xml", "w")
output_xml.write(builder.to_xml)
output_xml.close