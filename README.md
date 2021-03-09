# FHEM-Tesla

---------

Bugfix Version for Authentification problem.

---------

CAUTION: You need to set "Login" of Tesa Connection AND "init" at the CAR each time you restart FHEM

---------

Monitor and control your Tesla vehicles in the FHEM smart home environment.

Enter this command in your FHEM command line to install the Tesla plugin:

update all https://raw.githubusercontent.com/BAngel87/FHEM-Tesla/master/controls_tesla.txt

Then check the TeslaConnection device description in your FHEM Commandref.

Use my referral code to get benefits when buying your new Tesla: http://ts.la/stefan1473

Set Acces Token in:

attr NAME AccessToken by

Getting AccessToken from PHPSkript "PHPScriptTeslaLogin",  PHP Skript not working anymore, getting Token, from e.g. teslafi,....

1. Adding Name and Passwort in last row of script
2. Run with: php -f PHPScriptTeslaLogin.php 
3. Paste Token "qts-*******" in fhem attr.
4. set teslaconn Login
5. set TeslaCar init

--> GO

Credits goes to:
https://github.com/timdorr/tesla-api/discussions/283

and
mrmops:
https://forum.fhem.de/index.php/topic,74341.165.html
