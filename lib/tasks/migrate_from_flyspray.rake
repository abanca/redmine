# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

desc 'FlySpray migration script'

require 'active_record'
require 'iconv'
require 'pp'

namespace :redmine do
task :migrate_from_flyspray => :environment do

  module FlySprayMigrate

    class FlySprayUser < ActiveRecord::Base
      set_table_name :flyspray_users

      def firstname
        @firstname = real_name.blank? ? username : real_name.split.first[0..29]
        @firstname.gsub!(/[^\w\s\'\-]/i, '')
        @firstname 
      end

      def lastname
        @lastname = real_name.blank? ? '-' : real_name.split[1..-1].join(' ')[0..29]
        @lastname.gsub!(/[^\w\s\'\-]/i, '')
        @lastname = '-' if @lastname.blank?
        @lastname 
      end
    end


    def self.migrate(group_name)
      # Users
      print "Migrating users"
      #User.delete_all "login <> 'admin'"
      users_map = {}
      users_migrated = 0
      
      group = Group.find(:first, :conditions => {:lastname => group_name}) unless group_name.blank?
      print "Group is: #{group.lastname}";


      FlySprayUser.find(:all).each do |user|
        print "Trying to import #{user.user_name} => #{user.email_address} "
        u = User.find_by_login(user.user_name)
        if !u
          print " Not exists.Importing"
          u = User.new :firstname => encode(user.firstname),
    				 :lastname => encode(user.lastname),
    				 :mail => user.email_address
          u.login = user.user_name
          u.status = User::STATUS_LOCKED if user.account_enabled != 1
          u.admin = false;
          u.auth_source_id = 1;
          u.language = 'es';
          next unless u.save!
          if group
              group.users << u
          end
          users_migrated += 1
          users_map[user.id] = u.id
        else
          print "Exits. Not importing"
        end
        print ".\n"
       end
      puts

      puts

      puts
      puts "Users:           #{users_migrated}/#{FlySprayUser.count}"
    end

    def self.encoding(charset)
      @ic = Iconv.new('UTF-8', charset)
    rescue Iconv::InvalidEncoding
      return false
    end

    def self.establish_connection(params)
      constants.each do |const|
        klass = const_get(const)
        next unless klass.respond_to? 'establish_connection'
        klass.establish_connection params
      end
    end

    def self.encode(text)
      @ic.iconv text
    rescue
      text
    end
  end

  puts
  if Redmine::DefaultData::Loader.no_data?
    puts "Redmine configuration need to be loaded before importing data."
    puts "Please, run this first:"
    puts
    puts "  rake redmine:load_default_data RAILS_ENV=\"#{ENV['RAILS_ENV']}\""
    exit
  end



  # Default FlySpray database settings
  db_params = {:adapter => 'mysql',
               :database => 'flyspray',
               :host => 'localhost',
               :username => 'root',
               :password => '' }

  puts
  puts "Please enter settings for your Flyspray database"
  [:adapter, :host, :database, :username, :password].each do |param|
    print "#{param} [#{db_params[param]}]: "
    value = STDIN.gets.chomp!
    db_params[param] = value unless value.blank?
  end

  while true
    print "encoding [UTF-8]: "
    STDOUT.flush
    encoding = STDIN.gets.chomp!
    encoding = 'UTF-8' if encoding.blank?
    break if FlySprayMigrate.encoding encoding
    puts "Invalid encoding!"
  end
  puts


  puts "Plaase enter de default group to assign new users"
  default_group = STDIN.gets.chomp!


  # Make sure bugs can refer bugs in other projects
  Setting.cross_project_issue_relations = 1 if Setting.respond_to? 'cross_project_issue_relations'

  # Turn off email notifications
  Setting.notified_events = []

  FlySprayMigrate.establish_connection db_params
  FlySprayMigrate.migrate default_group
end
end
