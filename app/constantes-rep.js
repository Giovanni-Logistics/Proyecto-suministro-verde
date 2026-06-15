// constantes-rep.js — fuente única de verdad para constantes de Damu SGC (Ley REP)
// Cargar ANTES de auth-guard.js en toda página de app/ que necesite estas constantes.
window.DAMU = {

  // Tarifas por categoría REP (CLP/tonelada) y factor CO₂e (t CO₂e por t recolectada)
  // precioMercado = precio de venta estimado del material recuperado (CLP/t)
  tarifas: {
    envases:    { reco: 18000, trans: 12000, val: 22000, co2: 0.8, precioMercado: 120000 },
    neumaticos: { reco: 25000, trans: 18000, val: 30000, co2: 1.4, precioMercado:  30000 },
    pilas:      { reco: 35000, trans: 20000, val: 45000, co2: 0.4, precioMercado: 180000 },
    raee:       { reco: 40000, trans: 25000, val: 50000, co2: 1.1, precioMercado: 120000 },
    aceites:    { reco: 22000, trans: 15000, val: 28000, co2: 0.9, precioMercado:  40000 },
  },

  // Parámetros logísticos por defecto
  rendimDefault: 12,    // km/L
  dieselDefault: 1200,  // CLP/L
  co2PorLitro:   2.68,  // kg CO₂e por litro de diésel quemado

  // Meta mínima Ley REP Chile (Decreto 12, Art. 48)
  metaMinima: 0.25,

  // Catálogo de categorías REP
  categorias: ['envases', 'neumaticos', 'pilas', 'raee', 'aceites'],

  catLabel: {
    envases: 'Envases', neumaticos: 'Neumáticos',
    pilas: 'Pilas/Bat.', raee: 'RAEE', aceites: 'Aceites',
  },

  catIcono: {
    envases: '📦', neumaticos: '🛞', pilas: '🔋', raee: '🖥️', aceites: '🛢️',
  },

  // Colores de marca por categoría (usados en Chart.js y marcadores)
  catColor: {
    envases: '#059669', neumaticos: '#475569',
    pilas: '#d97706', raee: '#2563eb', aceites: '#ea580c',
  },

  // Centros de valorización REP en Santiago RM
  centros: {
    envases:    { nombre: 'Centro REP Envases — San Bernardo',  label: 'Centro Envases',    lat: -33.5949, lng: -70.6987 },
    neumaticos: { nombre: 'Centro REP Neumáticos — Pudahuel',   label: 'Centro Neumáticos', lat: -33.4474, lng: -70.8255 },
    pilas:      { nombre: 'Centro REP Pilas/Bat. — Quilicura',  label: 'Centro Pilas/Bat.', lat: -33.3581, lng: -70.7341 },
    raee:       { nombre: 'Centro REP RAEE — Maipú',            label: 'Centro RAEE',       lat: -33.5171, lng: -70.7614 },
    aceites:    { nombre: 'Centro REP Aceites — Til-Til',       label: 'Centro Aceites',    lat: -33.0816, lng: -70.9256 },
  },
};
