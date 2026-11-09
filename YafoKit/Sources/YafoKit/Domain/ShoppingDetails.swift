import Foundation

/// Menge und Details eines Einkaufsartikels als Bausteine, getrennt durch Kommas
/// („4, AA (Mignon)“). Die Schnellauswahl im Detailblatt schaltet Bausteine an und aus.
nonisolated public enum ShoppingDetails {
    /// Mengen zum Antippen.
    public static let amounts = ["1", "2", "3", "4", "6", "10"]

    public static func tokens(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func contains(_ token: String, in text: String) -> Bool {
        tokens(text).contains { same($0, token) }
    }

    /// Schaltet einen Baustein an oder aus. Reine Zahlen schließen sich gegenseitig aus und
    /// stehen vorn; alles andere wird hinten angehängt.
    public static func toggle(_ token: String, in text: String) -> String {
        var list = tokens(text)
        if let index = list.firstIndex(where: { same($0, token) }) {
            list.remove(at: index)
        } else if isAmount(token) {
            list.removeAll(where: isAmount)
            list.insert(token, at: 0)
        } else {
            list.append(token)
        }
        return list.joined(separator: ", ")
    }

    /// Typen, Sorten oder Größen zum Artikel, in der Sprache des Geräts; leer, wenn es keine gibt.
    public static func variants(for name: String,
                                languageCode: String? = Locale.current.language.languageCode?.identifier) -> [String] {
        guard let article = ShoppingCatalog.article(for: name),
              let entry = variantTable[article.germanNames[0]] else { return [] }
        return (languageCode == "de" ? entry.de : entry.en).components(separatedBy: "|")
    }

    static func isAmount(_ token: String) -> Bool { Int(token) != nil }

    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Schlüssel: erster deutscher Name der Katalog-Gruppe.
    static let variantTable: [String: (de: String, en: String)] = [
        // Obst & Gemüse
        "Äpfel": ("rot|grün|Elstar|Braeburn|Pink Lady|Bio", "Red|Green|Elstar|Braeburn|Pink Lady|Organic"),
        "Tomaten": ("Rispentomaten|Cherrytomaten|Fleischtomaten|Romatomaten|Bio", "On the vine|Cherry|Beefsteak|Roma|Organic"),
        "Kartoffeln": ("festkochend|vorwiegend festkochend|mehligkochend|Drillinge|Bio", "Waxy|All-purpose|Floury|Baby potatoes|Organic"),
        "Zwiebeln": ("gelb|rot|Gemüsezwiebel|Schalotten", "Yellow|Red|Sweet onion|Shallots"),
        "Paprika": ("rot|gelb|grün|Spitzpaprika|Mix", "Red|Yellow|Green|Pointed|Mixed"),
        "Bananen": ("grün|reif|Bio", "Green|Ripe|Organic"),
        "Salat": ("Kopfsalat|Eisberg|Rucola|Feldsalat|Mix", "Butterhead|Iceberg|Arugula|Lamb's lettuce|Mix"),
        // Brot
        "Brot": ("Vollkorn|Weizen|Roggen|Dinkel|geschnitten|Toast", "Whole grain|Wheat|Rye|Spelt|Sliced|Toast"),
        "Brötchen": ("Weizen|Vollkorn|Körner|Laugen|zum Aufbacken", "White|Whole grain|Seeded|Pretzel|Bake-off"),
        // Fleisch
        "Fleisch": ("Rind|Schwein|gemischt|Bio", "Beef|Pork|Mixed|Organic"),
        "Hähnchen": ("Brust|Schenkel|Flügel|ganz|Bio", "Breast|Thighs|Wings|Whole|Organic"),
        "Wurst": ("Salami|Schinken|Lyoner|Geflügel|vegetarisch", "Salami|Ham|Bologna|Poultry|Vegetarian"),
        "Fisch": ("Lachs|Thunfisch|Kabeljau|frisch|TK", "Salmon|Tuna|Cod|Fresh|Frozen"),
        // Kühlregal
        "Milch": ("1,5 %|3,5 %|laktosefrei|H-Milch|Bio", "1.5%|3.5%|Lactose-free|UHT|Organic"),
        "Butter": ("gesalzen|ungesalzen|streichzart|Bio", "Salted|Unsalted|Spreadable|Organic"),
        "Käse": ("Scheiben|gerieben|am Stück|Gouda|Emmentaler|Mozzarella", "Sliced|Grated|Block|Gouda|Emmental|Mozzarella"),
        "Eier": ("6er|10er|Bio|Freiland|Größe M|Größe L", "6 pack|10 pack|Organic|Free range|Size M|Size L"),
        "Joghurt": ("Natur|Frucht|griechisch|laktosefrei|Bio", "Plain|Fruit|Greek|Lactose-free|Organic"),
        "Sahne": ("Schlagsahne|Kochsahne|saure Sahne|Schmand", "Whipping cream|Cooking cream|Sour cream|Crème fraîche"),
        // Vorrat
        "Nudeln": ("Spaghetti|Penne|Fusilli|Farfalle|Vollkorn|glutenfrei", "Spaghetti|Penne|Fusilli|Farfalle|Whole wheat|Gluten-free"),
        "Reis": ("Basmati|Jasmin|Langkorn|Risotto|Milchreis", "Basmati|Jasmine|Long grain|Risotto|Pudding rice"),
        "Mehl": ("Type 405|Type 550|Type 1050|Dinkel|Vollkorn", "All-purpose|Bread flour|Spelt|Whole wheat"),
        "Zucker": ("weiß|braun|Puderzucker|Gelierzucker", "White|Brown|Powdered|Jam sugar"),
        "Öl": ("Olivenöl|Sonnenblumenöl|Rapsöl|Bratöl", "Olive oil|Sunflower oil|Canola oil|Frying oil"),
        "Müsli": ("Knusper|Früchte|Schoko|ohne Zucker|Haferflocken", "Crunchy|Fruit|Chocolate|No sugar|Oats"),
        "Kaffee": ("Bohnen|gemahlen|Pads|Kapseln|entkoffeiniert", "Beans|Ground|Pods|Capsules|Decaf"),
        "Tee": ("schwarz|grün|Früchte|Kräuter|Pfefferminz|Kamille", "Black|Green|Fruit|Herbal|Peppermint|Chamomile"),
        // Süßes & Getränke
        "Schokolade": ("Vollmilch|Zartbitter|weiß|Nuss", "Milk|Dark|White|Nut"),
        "Chips": ("Paprika|gesalzen|Sour Cream|Tortilla", "Paprika|Salted|Sour cream|Tortilla"),
        "Eis": ("Vanille|Schoko|Erdbeer|am Stiel|Becher", "Vanilla|Chocolate|Strawberry|On a stick|Tub"),
        "Wasser": ("still|medium|spritzig|6er-Pack|Kiste", "Still|Lightly sparkling|Sparkling|6 pack|Crate"),
        "Saft": ("Apfel|Orange|Multivitamin|Traube|ohne Fruchtfleisch", "Apple|Orange|Multivitamin|Grape|No pulp"),
        "Cola": ("normal|Zero|Light|Flaschen|Dosen", "Regular|Zero|Diet|Bottles|Cans"),
        "Bier": ("Kiste|Sixpack|Dosen|alkoholfrei|Pils|Weizen", "Crate|Six-pack|Cans|Alcohol-free|Lager|Wheat beer"),
        "Wein": ("rot|weiß|rosé|trocken|lieblich", "Red|White|Rosé|Dry|Sweet"),
        "Pizza": ("Margherita|Salami|Thunfisch|vegetarisch", "Margherita|Salami|Tuna|Vegetarian"),
        // Haushalt & Drogerie
        "Toilettenpapier": ("3-lagig|4-lagig|8 Rollen|16 Rollen|recycelt", "3-ply|4-ply|8 rolls|16 rolls|Recycled"),
        "Küchenrolle": ("2 Rollen|4 Rollen|8 Rollen", "2 rolls|4 rolls|8 rolls"),
        "Spülmittel": ("Tabs|Pulver|Gel|Klarspüler|Salz", "Tabs|Powder|Gel|Rinse aid|Salt"),
        "Waschmittel": ("Pulver|flüssig|Caps|Color|Vollwaschmittel|Feinwaschmittel", "Powder|Liquid|Pods|Color|Heavy duty|Delicates"),
        "Müllbeutel": ("10 l|20 l|35 l|60 l|mit Zugband", "10 l|20 l|35 l|60 l|Drawstring"),
        "Batterien": ("AAA (Micro)|AA (Mignon)|C (Baby)|D (Mono)|9V (E-Block)|Knopfzelle", "AAA|AA|C|D|9V|Button cell"),
        "Glühbirne": ("E27|E14|GU10|warmweiß|kaltweiß", "E27|E14|GU10|Warm white|Cool white"),
        "Zahnpasta": ("Kinder|sensitiv|Whitening|Zahnbürste weich|Zahnbürste mittel", "Kids|Sensitive|Whitening|Soft toothbrush|Medium toothbrush"),
        "Duschgel": ("Kinder|sensitiv|Männer|Frauen", "Kids|Sensitive|Men|Women"),
        // Baby & Tier
        "Windeln": ("Größe 1|Größe 2|Größe 3|Größe 4|Größe 5|Größe 6|Pants", "Size 1|Size 2|Size 3|Size 4|Size 5|Size 6|Pants"),
        "Feuchttücher": ("sensitiv|parfümfrei|Großpackung", "Sensitive|Fragrance-free|Value pack"),
        "Babynahrung": ("Pre|1er|2er|ab 4. Monat|ab 6. Monat|ab 1 Jahr", "Stage 1|Stage 2|Stage 3|From 4 months|From 6 months|From 1 year"),
        "Katzenfutter": ("Nassfutter|Trockenfutter|Streu|Leckerli", "Wet food|Dry food|Litter|Treats"),
        "Hundefutter": ("Nassfutter|Trockenfutter|Leckerli", "Wet food|Dry food|Treats"),
    ]
}
