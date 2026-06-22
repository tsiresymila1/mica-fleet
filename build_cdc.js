const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat, TabStopType, TabStopPosition,
  TableOfContents, HeadingLevel, BorderStyle, WidthType, ShadingType,
  VerticalAlign, PageNumber, PageBreak
} = require(require("child_process").execSync("npm root -g").toString().trim() + "/docx");

const BLUE = "1F4E79", LBLUE = "D5E8F0", GREEN = "2E7D32", GREY = "F2F2F2", ORANGE = "C55A11";
const CW = 9360; // content width US Letter 1" margins

const border = { style: BorderStyle.SINGLE, size: 1, color: "BFBFBF" };
const borders = { top: border, bottom: border, left: border, right: border };
const cellMargins = { top: 60, bottom: 60, left: 120, right: 120 };

// helpers
const H1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(t)] });
const H2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)] });
const H3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(t)] });
const P = (t, opts = {}) => new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text: t, ...opts })] });
const BUL = (t) => new Paragraph({ numbering: { reference: "bul", level: 0 }, spacing: { after: 40 }, children: parseRuns(t) });
const BUL2 = (t) => new Paragraph({ numbering: { reference: "bul", level: 1 }, spacing: { after: 40 }, children: parseRuns(t) });

// parse **bold** segments
function parseRuns(t) {
  const out = [];
  t.split(/(\*\*[^*]+\*\*)/).forEach(seg => {
    if (!seg) return;
    if (seg.startsWith("**") && seg.endsWith("**")) out.push(new TextRun({ text: seg.slice(2, -2), bold: true }));
    else out.push(new TextRun(seg));
  });
  return out.length ? out : [new TextRun(t)];
}

function table(headers, rows, widths) {
  const tot = widths.reduce((a, b) => a + b, 0);
  const headerRow = new TableRow({
    tableHeader: true,
    children: headers.map((h, i) => new TableCell({
      borders, width: { size: widths[i], type: WidthType.DXA }, margins: cellMargins,
      shading: { fill: BLUE, type: ShadingType.CLEAR },
      verticalAlign: VerticalAlign.CENTER,
      children: [new Paragraph({ children: [new TextRun({ text: h, bold: true, color: "FFFFFF", size: 20 })] })]
    }))
  });
  const bodyRows = rows.map((r, ri) => new TableRow({
    children: r.map((c, i) => new TableCell({
      borders, width: { size: widths[i], type: WidthType.DXA }, margins: cellMargins,
      shading: { fill: ri % 2 ? "FFFFFF" : GREY, type: ShadingType.CLEAR },
      verticalAlign: VerticalAlign.CENTER,
      children: String(c).split("\n").map(line => new Paragraph({ children: parseRuns(line).map(rn => { rn.options ? rn.options.size = 20 : null; return rn; }) }))
    }))
  }));
  return new Table({ width: { size: tot, type: WidthType.DXA }, columnWidths: widths, rows: [headerRow, ...bodyRows] });
}

const children = [];

// ===== COVER =====
children.push(
  new Paragraph({ spacing: { before: 2400, after: 0 }, alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "CAHIER DES CHARGES FONCTIONNEL", bold: true, size: 48, color: BLUE })] }),
  new Paragraph({ spacing: { before: 200, after: 0 }, alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "Application Mobile de Traçabilité du Mica Artisanal", bold: true, size: 36, color: "404040" })] }),
  new Paragraph({ spacing: { before: 120, after: 600 }, alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "Collecte terrain offline-first – Mine → Transport → Dépôt – Intégration Odoo", italics: true, size: 24, color: "606060" })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: BLUE, space: 4 } }, children: [new TextRun("")] }),
);
const coverRows = [
  ["Projet", "Système de traçabilité digitale du mica artisanal"],
  ["Commanditaire", "RADORAN"],
  ["Composant", "Application mobile Android (terrain)"],
  ["Système cible", "Odoo (serveur central + API de synchronisation)"],
  ["Version", "1.0"],
  ["Date", "22 juin 2026"],
  ["Confidentialité", "Document interne"],
];
children.push(new Paragraph({ spacing: { before: 600 }, children: [] }));
children.push(new Table({
  width: { size: 7000, type: WidthType.DXA }, columnWidths: [2400, 4600],
  alignment: AlignmentType.CENTER,
  rows: coverRows.map((r, i) => new TableRow({ children: [
    new TableCell({ borders, width: { size: 2400, type: WidthType.DXA }, margins: cellMargins, shading: { fill: LBLUE, type: ShadingType.CLEAR },
      children: [new Paragraph({ children: [new TextRun({ text: r[0], bold: true, size: 22 })] })] }),
    new TableCell({ borders, width: { size: 4600, type: WidthType.DXA }, margins: cellMargins,
      children: [new Paragraph({ children: [new TextRun({ text: r[1], size: 22 })] })] }),
  ]}))
}));
children.push(new Paragraph({ children: [new PageBreak()] }));

// ===== TOC =====
children.push(new Paragraph({ children: [new TextRun({ text: "Sommaire", bold: true, size: 32, color: BLUE })], spacing: { after: 200 } }));
children.push(new TableOfContents("Sommaire", { hyperlink: true, headingStyleRange: "1-2" }));
children.push(new Paragraph({ children: [new PageBreak()] }));

// ===== 1. CONTEXTE =====
children.push(H1("1. Contexte et objet du document"));
children.push(H2("1.1 Objet"));
children.push(P("Ce cahier des charges définit les exigences fonctionnelles, techniques et opérationnelles de l’application mobile Android de traçabilité du mica artisanal. L’application constitue le point de collecte des données sur le terrain : elle accompagne le fournisseur depuis le chargement à la mine jusqu’à l’arrivée au dépôt, capture des preuves géolocalisées, et alimente le serveur Odoo (module de traçabilité, module de cartographie minière et portail fournisseur)."));
children.push(H2("1.2 Contraintes opérationnelles"));
[
  "Extraction artisanale dispersée, souvent sans mise en sac à la mine.",
  "Regroupement de produits issus de plusieurs mines (jusqu’à 3) sur un même chargement.",
  "Zones à faible ou sans couverture réseau → fonctionnement **offline-first** obligatoire.",
  "Multiples changements de transporteurs (transbordements).",
  "Besoin de preuves visuelles géolocalisées et infalsifiables.",
  "Risques de mélange de lots et de fraude sur l’origine.",
].forEach(t => children.push(BUL(t)));
children.push(H2("1.3 Objectifs de l’application mobile"));
[
  "Garantir l’origine du mica par preuve GPS + photo prise dans l’application.",
  "Assurer la traçabilité multi-mines sur un même chargement.",
  "Suivre le transport et les transbordements avec validation GPS.",
  "Lire automatiquement la plaque du camion (OCR) avec validation manuelle de secours.",
  "Fonctionner entièrement hors ligne puis synchroniser automatiquement.",
  "Alimenter le score de traçabilité et le système de bonus.",
  "Déclencher la création automatique d’un bon de commande brouillon dans Odoo.",
].forEach(t => children.push(BUL(t)));
children.push(H2("1.4 Documents de référence"));
children.push(table(
  ["Document", "Composant couvert"],
  [
    ["CDC – Traçabilité Digitale du Mica Artisanal", "Application mobile (présent document)"],
    ["CDC – Portail Fournisseur v2.0", "Portail web Odoo de consultation"],
    ["CDC – Cartographie Minière de RADORAN", "Module Odoo de cartographie et référentiel des mines"],
  ], [5000, 4360]));

// ===== 2. PERIMETRE =====
children.push(H1("2. Périmètre"));
children.push(H2("2.1 Dans le périmètre"));
[
  "Authentification fournisseur et accs offline.",
  "Création et gestion d’un chargement (1 à 3 mines).",
  "Capture photo géolocalisée et OCR plaque.",
  "Gestion du transport, transbordement et arrivée au dépôt.",
  "Calcul / pré-calcul du score de traçabilité et détection anti-fraude locale.",
  "Stockage local chiffré et synchronisation avec Odoo.",
].forEach(t => children.push(BUL(t)));
children.push(H2("2.2 Hors périmètre"));
[
  "Calcul définitif et immuable du score et du bonus (réalisé côté Odoo après synchronisation).",
  "Validation cartographique des mines (module Odoo Cartographie).",
  "Comptabilité, facturation et paiements (Odoo / portail fournisseur).",
].forEach(t => children.push(BUL(t)));

// ===== 3. ACTEURS =====
children.push(H1("3. Acteurs et rôles"));
children.push(table(
  ["Acteur", "Rôle sur l’application mobile", "Accès"],
  [
    ["Fournisseur / opérateur terrain", "Crée les chargements, prend les photos, déclare mines et quantités", "Création (données propres)"],
    ["Responsable dépôt", "Valide l’arrivée au dépôt, saisit chauffeur / permis / lot", "Validation arrivée"],
    ["Administrateur (Odoo)", "Paramètre délais, rayons GPS, mines, dépôts, seuils de bonus", "Hors app (Odoo)"],
    ["Contrôleur / auditeur", "Consulte les preuves (lecture seule)", "Hors app (Odoo)"],
  ], [2600, 5160, 1600]));

// ===== 4. ARCHITECTURE =====
children.push(H1("4. Architecture et principes"));
[
  "**Offline-first** : toute opération terrain fonctionne sans réseau ; la synchronisation est différée et automatique.",
  "**Base locale** sur l’appareil (données + photos) avec chiffrement au repos.",
  "**API de synchronisation** bidirectionnelle vers Odoo (file d’attente, reprise sur erreur, anti-doublon par identifiant unique).",
  "**Journal immuable** des événements avec hash des photos (préparé pour blockchain en phase avancée).",
  "**Plateforme** : Android (smartphone terrain). Caméra, GPS et stockage requis.",
].forEach(t => children.push(BUL(t)));

// ===== 5. AUTH =====
children.push(H1("5. Authentification et accès"));
[
  "Connexion par **identifiant fournisseur unique** ; le compte doit être actif dans Odoo.",
  "Accès strictement limité aux données du fournisseur connecté.",
  "Authentification utilisable **hors ligne** (jeton / identifiants mis en cache de manière sécurisée).",
  "Le responsable dépôt dispose d’un accès dédié pour la validation d’arrivée.",
].forEach(t => children.push(BUL(t)));

// ===== 6. PROCESSUS METIER =====
children.push(H1("6. Processus métier"));

children.push(H2("6.1 Étape 1 – Chargement à la mine"));
children.push(P("Le fournisseur se connecte, sélectionne la mine, puis saisit les données du produit et prend la photo obligatoire."));
children.push(H3("Données saisies manuellement"));
["Référence produit.", "Couleur du mica.", "Quantité estimée."].forEach(t => children.push(BUL(t)));
children.push(H3("Photo obligatoire (prise dans l’app, jamais importée)"));
["Camion à moitié chargé.", "Plaque d’immatriculation visible.", "Mica clairement visible (échantillon en main)."].forEach(t => children.push(BUL(t)));
children.push(P("L’application assiste la prise de vue (cadrage, netteté, lisibilité de la plaque).", { italics: true }));
children.push(H3("Données capturées automatiquement"));
["GPS (latitude, longitude, précision / HDOP).", "Date et heure.", "Plaque camion (OCR).", "Nom de la carrière, district, commune, région (depuis le référentiel mines).", "Identifiant unique de l’appareil."].forEach(t => children.push(BUL(t)));
children.push(P("Un identifiant unique de chargement est généré automatiquement, au format **MICA-YYYY-XXXX**."));

children.push(H2("6.2 Étape 2 – Chargement multi-mines"));
[
  "Bouton **Ajouter une mine** pour compléter le chargement.",
  "**Maximum 3 mines** par chargement.",
  "Photo et jeu de données **obligatoires pour chaque mine** ajoutée.",
  "Bouton **Valider** une fois les 1 à 3 mines renseignées.",
].forEach(t => children.push(BUL(t)));

children.push(H2("6.3 Étape 3 – Transport et transbordement"));
children.push(P("Le transport peut être direct vers le dépôt ou passer par un point de collecte (transbordement)."));
children.push(P("En cas de transbordement :", { bold: true }));
[
  "Photo de **déchargement** du camion A obligatoire (GPS, plaque OCR, mica, date/heure).",
  "Photo de **rechargement** sur le camion B obligatoire (nouvelle plaque enregistrée).",
  "Vérification GPS du transbordement : distance entre déchargement et rechargement ≤ rayon paramétré (ex. 20 m).",
  "Si distance > rayon → alerte et impact sur le score.",
].forEach(t => children.push(BUL(t)));

children.push(H2("6.4 Étape 4 – Arrivée au dépôt"));
children.push(P("Le responsable dépôt (connecté au réseau) réceptionne le chargement."));
children.push(H3("Champs obligatoires à l’arrivée"));
["Nom du chauffeur.", "Numéro de permis.", "Photo du permis (optionnel).", "Numéro de lot par couleur ou référence.", "Photo d’arrivée géolocalisée (déchargement, plaque, mica)."].forEach(t => children.push(BUL(t)));
children.push(H3("Validation automatique"));
[
  "Vérification de l’immatriculation (cohérence départ → arrivée).",
  "Vérification GPS dans la zone du dépôt (rayon paramétrable, ex. 20 m).",
  "Détection automatique du dépôt concerné (gestion multi-dépôts).",
  "Validation finale si toutes les données sont cohérentes.",
].forEach(t => children.push(BUL(t)));

// ===== 7. FONCTIONS TECHNIQUES =====
children.push(H1("7. Fonctions techniques de capture"));
children.push(H2("7.1 Géolocalisation GPS"));
[
  "Capture de la position à chaque photo, avec précision (HDOP).",
  "Comparaison avec le point autorisé de la mine (référentiel cartographie) et son rayon.",
  "Détection de **mock location / GPS falsifié** : si détecté, chargement rejeté.",
  "Temps de présence minimum sur site paramétrable (recommandé : 5 minutes).",
].forEach(t => children.push(BUL(t)));
children.push(H2("7.2 Photo et preuve"));
[
  "Photo **prise via l’application uniquement** (import galerie interdit).",
  "Conservation des métadonnées : GPS, orientation, horodatage.",
  "**Hash (SHA-256)** calculé à la capture → photo infalsifiable.",
  "Première capture obligatoire avant de poursuivre l’étape.",
].forEach(t => children.push(BUL(t)));
children.push(H2("7.3 Reconnaissance de plaque (OCR)"));
[
  "Lecture automatique de la plaque sur la photo.",
  "**Validation manuelle** proposée si la reconnaissance échoue.",
  "Contrôle de cohérence de la plaque sur tout le trajet (départ → arrivée).",
].forEach(t => children.push(BUL(t)));
children.push(H2("7.4 Contrôles anti-fraude"));
[
  "Un même camion ne peut pas être à deux endroits en même temps (cohérence temporelle et vitesse).",
  "Détection des temps de trajet impossibles.",
  "Limitation des chargements simultanés par camion.",
  "Historique des plaques et des fournisseurs.",
].forEach(t => children.push(BUL(t)));

// ===== 8. DONNEES =====
children.push(H1("8. Données à enregistrer"));
children.push(table(
  ["Entité", "Champs"],
  [
    ["Fournisseur", "Identifiant, nom, statut actif"],
    ["Mine", "Nom carrière, GPS, district, commune, région, rayon autorisé"],
    ["Camion", "Plaque (OCR), historique"],
    ["Chargement", "ID unique (MICA-YYYY-XXXX), GPS, photo(s), couleur, référence, quantité estimée, date/heure, mines sources (1-3)"],
    ["Transbordement", "GPS déchargement, GPS rechargement, nouvelle plaque, photos"],
    ["Arrivée dépôt", "GPS, photo, chauffeur, n° permis, n° lot, dépôt détecté"],
  ], [2200, 7160]));

// ===== 9. SCORE =====
children.push(H1("9. Score de traçabilité et bonus"));
children.push(P("Le score est **100 % automatisé** : aucune intervention humaine n’est possible sur le calcul après synchronisation. L’application collecte et pré-contrôle les données ; le calcul définitif et immuable est réalisé côté Odoo. Le scoring s’organise en trois niveaux."));

children.push(H2("9.1 Niveau 1 – Éligibilité (Pass / Fail)"));
children.push(P("Si un seul critère éliminatoire échoue : score final = 0, bonus = 0 Ar/kg, statut = Rejeté."));
children.push(table(
  ["Critère éliminatoire", "Condition"],
  [
    ["GPS mine dans le rayon autorisé", "Point GPS dans le rayon de la mine défini par l’admin"],
    ["Photo mine valide", "Prise via l’app, claire, camion + mica visibles"],
    ["Fournisseur identifié et actif", "Compte valide et actif dans Odoo"],
    ["Mine autorisée et active", "Mine dans la liste des mines autorisées"],
    ["Données complètes et synchronisées", "Tous les champs obligatoires renseignés"],
    ["Maximum 3 mines par chargement", "Chargement ≤ 3 mines sources"],
    ["Dépôt reconnu et actif", "Dépôt de destination valide dans Odoo"],
    ["GPS non falsifié", "Aucune simulation de position (mock location) détectée"],
  ], [3400, 5960]));

children.push(H2("9.2 Niveau 2 – Score de conformité (100 points)"));
children.push(table(
  ["Catégorie", "Pts", "Règle de scoring"],
  [
    ["A. Traçabilité GPS", "20", "Distance au point autorisé : ≤ 20 m = 20 ; ≤ 50 m = 15 ; ≤ 100 m = 10 ; > 100 m = 0"],
    ["B. Respect des délais", "25", "Respecté = 25 ; +10 % = 18 ; +25 % = 12 ; +50 % et + = 0"],
    ["C. Cohérence transport", "20", "Plaque cohérente départ→arrivée + chronologie logique = 20 ; sinon 0"],
    ["D. Exactitude quantité", "20", "Écart poids déclaré vs pesé : ≤ 2 % = 20 ; ≤ 5 % = 15 ; ≤ 10 % = 10 ; > 10 % = 0"],
    ["E. Historique fournisseur", "15", "Taux conformité 90 j : ≥ 95 % = 15 ; ≥ 90 % = 12 ; ≥ 80 % = 7 ; < 80 % = 0"],
  ], [2800, 800, 5760]));
children.push(P("Score final = somme des points obtenus, sur 100.", { bold: true }));

children.push(H2("9.3 Niveau 3 – Bonus financier"));
[
  "Bonus accordé si **score ≥ 80 / 100** et tous critères éliminatoires satisfaits.",
  "Bonus maximum paramétrable par l’admin (ex. 10 Ar/kg).",
  "Bonus réel = Bonus max × (Score final / 100).",
  "Le seuil et le montant sont définis dans Odoo, jamais modifiables manuellement après capture.",
].forEach(t => children.push(BUL(t)));

// ===== 10. DELAIS =====
children.push(H1("10. Délais d’acheminement et rappels"));
children.push(H2("10.1 Paramètres administrateur"));
children.push(table(
  ["Étape", "Délai max (exemple par défaut)"],
  [
    ["Mine → Point de collecte", "24 h"],
    ["Point de collecte → Dépôt", "48 h"],
    ["Chargement → Validation finale", "24 h"],
    ["Transport direct → Dépôt", "72 h"],
  ], [5000, 4360]));
children.push(P("Les valeurs sont paramétrables dans Odoo ; celles ci-dessus sont indicatives.", { italics: true }));
children.push(H2("10.2 Rappels automatiques"));
["Notification au fournisseur avant échéance (ex. 80 % du délai).", "Alerte à échéance.", "Alerte délai dépassé (fournisseur + superviseur + Odoo)."].forEach(t => children.push(BUL(t)));
children.push(H2("10.3 Actions en cas de dépassement"));
["Score de traçabilité réduit.", "Bonus désactivé.", "Alerte administrateur et blocage de validation."].forEach(t => children.push(BUL(t)));

// ===== 11. OFFLINE =====
children.push(H1("11. Mode offline et synchronisation"));
[
  "Toutes les fonctions terrain disponibles **sans réseau**.",
  "Stockage local sécurisé (chiffrement) des données et photos.",
  "**Synchronisation automatique** dès connexion (notamment à l’arrivée au dépôt).",
  "File d’attente avec reprise sur erreur et dédoublonnage par identifiant unique.",
  "Indicateur d’état : synchronisé / en attente.",
].forEach(t => children.push(BUL(t)));

// ===== 12. SECURITE =====
children.push(H1("12. Sécurité et intégrité des données"));
[
  "Authentification fournisseur et accès cloisonné.",
  "Enregistrement offline chiffré localement.",
  "Signature numérique des photos (hash SHA-256) – impossible à modifier.",
  "Journal immuable des événements préparé pour blockchain.",
  "Détection GPS falsifié / mock location.",
  "Traçabilité consultable par le fournisseur (ses propres données uniquement).",
].forEach(t => children.push(BUL(t)));

// ===== 13. ODOO =====
children.push(H1("13. Intégration Odoo"));
children.push(P("À la synchronisation, l’application alimente Odoo et déclenche la création automatique des objets suivants :"));
["Bon de commande à l’état **Brouillon**.", "Fiche fournisseur et dépôt rattachés.", "Lots (par couleur / référence).", "Photos géolocalisées et coordonnées GPS.", "Score de traçabilité et statut bonus.", "Points GPS de transport rattachés à la mine d’origine (module cartographie)."].forEach(t => children.push(BUL(t)));

// ===== 14. EXIGENCES NON FONCT =====
children.push(H1("14. Exigences non fonctionnelles"));
children.push(table(
  ["Exigence", "Cible"],
  [
    ["Plateforme", "Android (smartphone terrain)"],
    ["Disponibilité hors ligne", "100 % des fonctions de collecte"],
    ["Simplicité", "Parcours guidé, saisie minimale, contrôles assistés"],
    ["Robustesse", "Reprise après coupure, aucune perte de donnée"],
    ["Performance", "Capture + enregistrement local fluides sur appareil d’entrée de gamme"],
    ["Sécurité", "Chiffrement au repos, hash photos, anti mock-location"],
    ["Langue", "Français"],
  ], [3000, 6360]));

// ===== 15. CRITERES ACCEPTATION =====
children.push(H1("15. Critères d’acceptation"));
[
  "Fonctionnement complet hors ligne vérifié.",
  "Synchronisation automatique sans doublon ni perte.",
  "Création automatique du bon de commande brouillon dans Odoo.",
  "Photo prise dans l’app uniquement, avec GPS + hash.",
  "Chargement multi-mines limité à 3, photo par mine.",
  "Validation GPS transbordement et arrivée dépôt opérationnelles.",
  "Rejet automatique en cas de critère éliminatoire non satisfait.",
].forEach(t => children.push(BUL(t)));

// ===== 16. PHASES =====
children.push(H1("16. Phases du projet"));
children.push(table(
  ["Phase", "Périmètre", "Priorité"],
  [
    ["Phase 1", "Application mobile : chargement, photo, GPS, multi-mines, offline, synchro Odoo", "Très haute"],
    ["Phase 2", "Validation dépôt, transbordement, délais et rappels, score", "Haute"],
    ["Phase 3", "Sécurité avancée : journal immuable, blockchain, audits", "Moyenne"],
  ], [1600, 6160, 1600]));

// ===== BUILD =====
const doc = new Document({
  creator: "RADORAN",
  title: "CDC Application Mobile Traçabilité Mica",
  styles: {
    default: { document: { run: { font: "Arial", size: 22 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 30, bold: true, color: BLUE, font: "Arial" },
        paragraph: { spacing: { before: 320, after: 160 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 25, bold: true, color: "2E5496", font: "Arial" },
        paragraph: { spacing: { before: 220, after: 120 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 22, bold: true, color: "404040", font: "Arial" },
        paragraph: { spacing: { before: 160, after: 80 }, outlineLevel: 2 } },
    ]
  },
  numbering: { config: [
    { reference: "bul", levels: [
      { level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 460, hanging: 260 } } } },
      { level: 1, format: LevelFormat.BULLET, text: "–", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 920, hanging: 260 } } } },
    ]},
  ]},
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } } },
    headers: { default: new Header({ children: [new Paragraph({
      border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: "BFBFBF", space: 2 } },
      children: [new TextRun({ text: "CDC – Application Mobile de Traçabilité du Mica – RADORAN", size: 16, color: "808080" })] })] }) },
    footers: { default: new Footer({ children: [new Paragraph({
      tabStops: [{ type: TabStopType.RIGHT, position: TabStopPosition.MAX }],
      children: [new TextRun({ text: "Document interne – Confidentiel", size: 16, color: "808080" }),
        new TextRun({ text: "\tPage ", size: 16, color: "808080" }),
        new TextRun({ children: [PageNumber.CURRENT], size: 16, color: "808080" }),
        new TextRun({ text: " / ", size: 16, color: "808080" }),
        new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 16, color: "808080" })] })] }) },
    children,
  }]
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync("CDC_Application_Mobile_Tracabilite_Mica.docx", buf);
  console.log("written", buf.length, "bytes");
});
