#!/bin/bash
set -e

dnf install -y nginx

cat > /usr/share/nginx/html/index.html <<EOF
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>Librería Tinta 2</title>
</head>
<body>
  <h1>Librería Tinta 2</h1>
  <p>Tu librería de barrio. Versión 2.</p>
  <p>Horario: de lunes a sábado, de 10:00 a 14:00 y de 17:00 a 20:00.</p>
  <p>Dirección: calle del Papel, 18, San Vicente del Raspeig.</p>
  <p>Recomendación de la semana: La sombra del viento.</p>
  <hr>
  <small>Desplegado por Borja en $(hostname) el $(date '+%d/%m/%Y %H:%M').</small>
</body>
</html>
EOF

systemctl enable --now nginx