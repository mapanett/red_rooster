#!/usr/bin/env ruby

#$:.unshift File.dirname(__FILE__) + "/../../lib"
require 'rubygems'
require 'camping'
require 'camping/session'
require 'mime/types'

Camping.goes :RedRooster

module RedRooster
   
end

module RedRooster::Models
   class Computer < Base
      has_many :schedules
      validates_format_of :mac, :with => /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/
      validates_uniqueness_of :mac, :name
      validates_presence_of :name
      validates_exclusion_of :name, :in => %w( Name )
      validates_exclusion_of :mac, :in => ['00:00:00:00:00:00']
      
      @@wake_cmd = "sudo etherwake"
      
      def before_create
         7.times do |i|
            schedules << Schedule.new(:day => i)
         end
      end
      
      def wake_cmd
         @@wake_cmd + " #{self.mac}"
      end
      
      def Computer.generate_cron
         cmds = []
         computers = Computer.find :all
         computers.each do |computer|
            computer.schedules.each do |schedule|
               if ! schedule.when.nil? && schedule.when != ''
                  m = schedule.when.match(/([0-9]{2}):([0-9]{2})/)
                  hr = m[1]
                  min = m[2]
                  cmds << "#{min}   #{hr}  *   *  #{schedule.day}   #{computer.wake_cmd}"
               end
            end
         end
         
         if cmds.length
            cron_out = IO.popen("crontab -", "w")
            cmds.each do |cmd|
               cron_out.puts cmd
            end
            cron_out.close
            #STDERR.puts(cmds)
         end
         
      end
   end
   
   class Schedule < Base
      validates_format_of :when, :with => /(^$)|(^(([0-1][0-9])|(2[0-3])):[0-5][0-9]$)/
      belongs_to :computer
   end
   
   class CreateTheBasics < V 1.0
      def self.up
         create_table :redrooster_computers, :force => true do |t|
            t.column :id,     :integer, :null => false
            t.column :name,   :string,  :limit => 255
            t.column :mac,    :string,  :limit => 255
         end
         
         create_table :redrooster_schedules, :force => true do |t|
            t.column :id,           :integer, :null => false
            t.column :computer_id,  :integer, :null => false
            t.column :day,          :integer, :null => false
            t.column :when,         :string,  :limit => 255
         end
         
      end
      def self.down
         drop_table :redrooster_computers
      end
   end
end

module RedRooster::Controllers
   class Index < R '/'
      def get
         @computers = Computer.find :all
         @new_computer = Computer.new
        
         render :index
      end
   end
   
   class Delete < R '/delete/(\d+)'
      def get(*args)
         @computer = Computer.find(args[0])
         render :delete
      end
      def post(*args)
         computer = Computer.find(args[0])
         computer.destroy()
         
         @message = "Computer #{computer.name} has been deleted."
         Computer.generate_cron
         render :message         
      end
   end
   
   class Add
      def get
         @computer = Computer.new
         render :add
      end
      def post
         #STDERR.puts(input.inspect)
         # can't use create! as it will not return an object
         @computer = Computer.create :name => input.name, :mac => input.mac
         
         if @computer.errors.count > 0
            render :add
         else
            @message = "New computer, #{@computer.name}, has been added."
            render :message
         end
      end
   end
   
   class Edit < R '/edit/(\d+)'
      def get(*args)
         #STDERR.puts(args.inspect)
         @computer = Computer.find(args[0])
         render :edit
      end
      
      def post(*args)
         @computer = Computer.find(args[0])
         
         if ( ! @computer )
            redirect Index
         end
         
         begin
            @computer.name = input.name
            @computer.mac = input.mac
            @computer.save!
            @message = '#{@computer.name} successfully updated.'
            
            Computer.generate_cron
         rescue ActiveRecord::RecordInvalid => record_invalid
            @message = record_invalid
         rescue ActiveRecord::RecordNotSaved => not_saved
            @message = not_saved
         end
         
         render :edit
      end
   end
   
   class Wake < R '/wake/(\w+)'
      def get(*args)
         @computer = Computer.find(args[0])
         if ( ! @computer )
            redirect Index
         end
         
         fork do
            exec @computer.wake_cmd
         end
         
         @message = "Magic wake up packet sent to #{@computer.name} - #{@computer.mac}"
         
         render :message
      end
   end
   
   class UpdateSchedule < R '/schedule/(\w+)'
      def get(*args)
         @computer = Computer.find(args[0])
         render :schedule
      end
      def post(*args)
         @computer = Computer.find(args[0])
         #STDERR.puts(@computer.schedules.inspect)
         #STDERR.puts(input[:when].inspect)
         
         all_ok = true
         @computer.schedules.each do |schedule|
            schedule.when = input[:when][schedule.id.to_s]
            all_ok = false unless schedule.save
         end
         
         if all_ok
            @message = "Schedule updated"
            Computer.generate_cron
         else
            @message = "Unable to update schedule.  Please use valid 24 hour times."
         end
         render :schedule
      end
   end

   class Stylesheet < R '/css/red_rooster.css'
      def get
         @headers['Content-Type'] = 'text/css'
         File.read(__FILE__).gsub(/.*__END__/m, '')
    end
  end
   
end

module RedRooster::Views
   def layout
      xhtml_transitional do
         head do
            title 'RedRooster'
            link :href=>R(Stylesheet), :rel=>'stylesheet', :type=>'text/css'
         end
         body do
            div.container! do
               div.header! do
                  h1.header { a 'RedRooster', :href => R(Index) }
               end
               div.content! do
                  self << yield
               end
               div.footer! do
                  p "© 2008 - Matthew Panetta."
               end
            end
         end
      end
   end
   
   def index
      div.message! {} 
      if @computers.empty?
         p 'No computers'
      else
         ul(:id => 'computer-list') do
            for computer in @computers
               li {
                  p "#{computer.mac} #{computer.name}"
                  span(:class => :actions) {
                     a 'schedule',  :href => R(UpdateSchedule, computer.id)
                     a 'edit',      :href=> R(Edit, computer.id)
                     a 'delete',    :href=> R(Delete, computer.id)
                     a 'wake',      :href=> R(Wake, computer.id)
                  }
                  
               }
            end
         end
      end
      div(:id => 'add-form') do
         #STDERR.puts(@new_computer.inspect)
         _form(@new_computer, :action => R(Add))
      end
   end
   
   def add
      h2 "Add Computer"
      _form(@computer, :action => R(Add))
   end
   
   def message
      _message
   end
   
   def edit
      h2 "Edit Computer"
      _form(@computer, :action => R(Edit, @computer.id))
   end
   
   def delete
      div(:class=>"message question") {
         form({:method => 'post', :action => R(Delete, @computer.id)}) {
            p "Are you sure you want to delete computer #{computer.name}? "
            input :type => 'submit', :value => 'Delete'
         }
      }
   end
   
   def schedule
      h2 "Update schedule for #{computer.name}"
      _message
      _schedule(@computer, :action => R(UpdateSchedule, @computer.id))
   end
   
   def _form(computer, opts)
      if computer.errors.count > 0
         div(:class=>"message"){
            p 'There were problems validating the computer.'
            ul(:class=>'errors') {
               computer.errors.each_full { |message|
                  li message
               }
            }
         }
      end
      
      form({:method => 'post'}.merge(opts)) do
         _input_text computer, :name => 'mac',  :default => '00:00:00:00:00:00'
         _input_text computer, :name => 'name', :default => 'Name'
         
         input :type => 'submit', :value => (computer.id ? 'Update':'Add')
      end
   end
   
   def _schedule(computer, opts)
      days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
      
      div( :id => "s_#{computer.id}", :class => 'schedule-container') do
         form({:method => 'post'}.merge(opts)) do
            table(:class => 'schedule-list') do
               tr {
                  computer.schedules.each do |schedule|
                     td { label "#{days[schedule.day]}", :for => "schedule_#{schedule.id}" }
                  end
               }
               tr {
                  computer.schedules.each do |schedule|
                     td { 
                        _input_text schedule, :name => "when", :id => schedule.id
                     }
                  end
               }
            end
            div(:class => 'schedule-actions') {
               input :value => "Update", :type => :submit   
            }
         end
      end
   end
   
   def _input_text(object, params)
      #object, name, default)
      params[:default] ||= ''
      
      name = params[:name]
      field_name = params[:name]
      id = params[:name].gsub(/_/, '-')
      if params.has_key?(:id)
         field_name = "#{field_name}[#{params[:id]}]"
         id = "#{id}-#{params[:id]}"
      end
      
      input :name => field_name, :id => id, :type => 'text',
         :value => (object[name].nil? ? params[:default]:object[name]),
         :class => (object.errors.invalid?(name) ? "input-error":"")
   end
   
   def _message
      if @message
         div(:class=>"message"){ @message }
      end
   end
end

def RedRooster.create
   RedRooster::Models.create_schema :assume => (RedRooster::Models::Computer.table_exists? ? 1.0: 0.0)
end

__END__
html,body,div,span,applet,object,iframe,h1,h2,h3,h4,h5,h6,p,blockquote,pre,a,abbr,acronym,address,big,cite,code,del,dfn,em,font,img,ins,kbd,q,s,samp,small,strike,strong,sub,sup,tt,var,dl,dt,dd,ol,ul,li,fieldset,form,label,legend,table,caption,tbody,tfoot,thead,tr,th,td {
border:0;
outline:0;
font-weight:inherit;
font-style:inherit;
font-size:100%;
font-family:inherit;
vertical-align:baseline;
margin:0;
padding:0;
}

:focus {
outline:0;
}

body {
line-height:1;
background:#FFF;
background-color:#E7E8D1;
color:#424242;
font-family:Arial,Helvetica,sans-serif;
height:100%;
}

ol,ul {
list-style:none;
}

table {
border-collapse:separate;
border-spacing:0;
}

caption,th,td {
text-align:left;
font-weight:400;
}

blockquote:before,blockquote:after,q:before,q:after {
content:"";
}

blockquote,q {
quotes:"" "";
}

#container {
background-color:transparent;
bottom:0;
top:0;
width:785px;
position:relative;
margin:0 auto;
}

#header {
background-color:#8e001c;
font-family:Arial,Helvetica,sans-serif;
margin:0 auto;
padding:15pt;
}

#content {
background-color:#fbf7e4;
min-height:500px;
margin:0 auto;
padding:5pt;
}

#footer {
border-top:solid 1px #8e001c;
background-color:#d3ceaa;
color:#666;
font-size:75%;
font-family:Arial,Helvetica,sans-serif;
text-align:center;
margin:0 auto;
padding:10px;
}

h1 {
color:#fcfae1;
font-size:203%;
}

h1 a {
color:#fcfae1;
text-decoration:none;
}

h2 {
font-size:150%;
border-bottom:solid 1px #ccc;
margin-bottom:15px;
}

input {
border:2px solid #424242;
color:#424242;
font-family:Helvetica,sans-serif;
font-size:105%;
margin-right:5pt;
padding:2pt;
}

input.input-error {
border:1px solid #ff2525;
background-color:#ffdada;
}

#computer-list>li {
border:2px solid #d3ceaa;
font-size:105%;
margin-bottom:2pt;
position:relative;
padding:4pt;
}

#computer-list>li p {
font-size:105%;
padding-top:5px;
vertical-align:middle;
}

table.schedule-list {
margin-bottom:2pt;
padding:2pt;
}

table.schedule-list tr {
margin-bottom:2pt;
}

table.schedule-list input[type='text'] {
width:4em;
text-align:center;
}

span.actions {
position:absolute;
top:0;
line-height:30px;
right:4px;
}

span.actions a,span.actions a:visited,span.actions a:active {
color:#4c1b1b;
text-decoration:none;
margin-left:5px;
}

span.actions a:hover {
text-decoration:underline;
}

input[type='button']:hover {
border:1px solid #000;
}

input[type='button'],input[type='submit'] {
background-color:#e7e8d1;
}

.message {
background-color:#ffff93;
border:solid 2px #efef67;
color:#333;
text-align:center;
width:400px;
margin:15px auto;
padding:10px;
}

.message p {
margin-bottom:.5em;
}

.message ul li {
margin-left:1em;
list-style:square;
}

form {
margin-top:15px;
}