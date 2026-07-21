Copy-Item -Path "campus.osm" -Destination "campus_clean.osm" -Force
Write-Host "Copiado campus.osm para campus_clean.osm"

Write-Host "Aplicando pesos..."
dart apply_wheelchair_weights.dart
dart fix_footway.dart
dart fix_osm.dart

Write-Host "Removendo IDs negativos do JOSM..."
python fix_negative.py

Write-Host "Extraindo dados para os JSON do App..."
dart extract_kerbs.dart
dart extract_parking.dart

Write-Host "Extraindo POIs..."
cd ../app
python extract_pois.py
cd ../backend

Write-Host "Removendo cache do GraphHopper..."
if (Test-Path "graph-cache") {
    Remove-Item -Recurse -Force graph-cache
    Write-Host "Cache removido!"
}

Write-Host "Atualizacao completa! Pode ligar o GraphHopper agora."
