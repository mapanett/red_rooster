Red Rooster
===========

A simple web interface to etherwake.

It uses cron to run etherwake at the desired times and since it will clobber any existing cron jobs it should be run as it's own user.  Etherwake needs to be run as root therefore the user that runs red rooster needs to be able run etherwake via sudo without requiring a password.  Here are the steps to accomplish this on Debian/Ubuntu: 

```
sudo apt-get install etherwake
sudo useradd -m red_rooster

sudo echo "red_rooster ALL = NOPASSWD: /usr/sbin/etherwake" > /etc/sudoers.d/red_rooster
sudo chmod 0440 /etc/sudoers.d/red_rooster
```

To start it up 

```
bundle install
camping red_rooster.rb
```

Then visit http://localhost:3301/