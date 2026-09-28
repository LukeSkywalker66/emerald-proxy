cd /opt/emerald-proxy/nginx
# Activar Producción y Staging con symlinks
ln -s ../templates-available/emerald.conf.template ./templates-enabled/emerald.conf.template
ln -s ../templates-available/emerald-test.conf.template ./templates-enabled/emerald-test.conf.template
ln -s ../templates-available/emerald-dev.conf.template ./templates-enabled/emerald-dev.conf.template

# borrarlos:
rm /opt/emerald-proxy/nginx/templates-enabled/emerald-dev.conf.template