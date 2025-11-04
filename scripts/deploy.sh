
# scope command and validate for project name argument

# Identify project server file

# Collect domain name and aliases from metadata or server conf file parse ?

# Check specific server file validity : nginx-t -c /path/to/your/nginx.conf

# ? # Rename server file with $(DOMAIN_NAME)? Or comnvetion ?

# cp file to server-conf (volume shared with nginxx, mounts to /etc/nginx/conf.d/)

# Trigeer certificate existance and validity checks through certbot container

# If new issual of certificates and admin email required, prompt user for admin email

# If fails, trigger certbot issual/renewal process

# Trigger server reload

