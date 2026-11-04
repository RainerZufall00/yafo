import Foundation

/// Abteilungen in der Reihenfolge, in der man typischerweise durch den Supermarkt läuft.
nonisolated public enum ShoppingCategory: String, CaseIterable, Sendable {
    case produce, bakery, meat, dairy, pantry, breakfast, snacks, drinks, frozen, household, hygiene, baby, pets, other

    public var emoji: String {
        switch self {
        case .produce: "🥦"
        case .bakery: "🥖"
        case .meat: "🥩"
        case .dairy: "🧀"
        case .pantry: "🍝"
        case .breakfast: "🥣"
        case .snacks: "🍫"
        case .drinks: "🧃"
        case .frozen: "🧊"
        case .household: "🧽"
        case .hygiene: "🧴"
        case .baby: "🍼"
        case .pets: "🐾"
        case .other: "🛒"
        }
    }

    /// Position im Laden; kleiner = früher.
    public var aisle: Int { Self.allCases.firstIndex(of: self)! }
}

/// Bekannter Artikel mit Piktogramm, Abteilung und Namen (erster Name = Anzeigename).
nonisolated public struct ShoppingArticle: Sendable, Hashable {
    public let emoji: String
    public let category: ShoppingCategory
    public let germanNames: [String]
    public let englishNames: [String]

    /// Anzeigename in der Sprache des Geräts (Deutsch oder Englisch).
    public func name(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        languageCode == "de" ? germanNames[0] : englishNames[0]
    }
}

/// Mitgelieferter Artikelkatalog: liefert Piktogramm und Abteilung für eingetippte Namen.
/// Deutsche Komposita werden über ihr Grundwort erkannt („Vollkornbrot“ → Brot).
nonisolated public enum ShoppingCatalog {
    public static func article(for name: String) -> ShoppingArticle? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        if let exact = index[key] { return exact }
        // Längstes bekanntes Grundwort am Ende („Vollmilch“) oder ein ganzes Wort („Milk 1.5%“).
        let words = Set(key.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return index.filter { name, _ in
            name.count >= 3 && (key.hasSuffix(name) || words.contains(name))
        }
        .max { $0.key.count < $1.key.count }?.value
    }

    public static func category(for name: String) -> ShoppingCategory {
        article(for: name)?.category ?? .other
    }

    public static func emoji(for name: String) -> String {
        article(for: name)?.emoji ?? ShoppingCategory.other.emoji
    }

    /// Katalogartikel, deren Name mit `prefix` beginnt, in der Sprache des Geräts.
    public static func suggestions(for prefix: String, languageCode: String? = Locale.current.language.languageCode?.identifier,
                                   limit: Int = 8) -> [String] {
        let key = normalize(prefix)
        guard !key.isEmpty else { return [] }
        // Passende Namen selbst vorschlagen („Majo“ → Majoran, nicht der erste Name der Gruppe);
        // passt nur die andere Sprache, den Anzeigenamen.
        var names: [String] = []
        for article in articles {
            let own = languageCode == "de" ? article.germanNames : article.englishNames
            let other = languageCode == "de" ? article.englishNames : article.germanNames
            let matching = own.filter { normalize($0).hasPrefix(key) }
            if !matching.isEmpty {
                names += matching
            } else if other.contains(where: { normalize($0).hasPrefix(key) }) {
                names.append(article.name(languageCode: languageCode))
            }
        }
        var seen = Set<String>()
        let unique = names.filter { seen.insert(normalize($0)).inserted }
        return Array(unique.sorted { $0.count < $1.count }.prefix(limit))
    }

    static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let index: [String: ShoppingArticle] = {
        var index: [String: ShoppingArticle] = [:]
        for article in articles {
            for name in article.germanNames + article.englishNames where index[normalize(name)] == nil {
                index[normalize(name)] = article
            }
        }
        return index
    }()

    private static func a(_ emoji: String, _ category: ShoppingCategory, _ german: String, _ english: String) -> ShoppingArticle {
        ShoppingArticle(emoji: emoji, category: category,
                        germanNames: german.components(separatedBy: "|"),
                        englishNames: english.components(separatedBy: "|"))
    }

    public static let articles: [ShoppingArticle] = [
        // Obst & Gemüse
        a("🍎", .produce, "Äpfel|Apfel", "Apples|Apple"),
        a("🍌", .produce, "Bananen|Banane", "Bananas|Banana"),
        a("🍐", .produce, "Birnen|Birne", "Pears|Pear"),
        a("🍊", .produce, "Orangen|Orange|Mandarinen|Clementinen", "Oranges|Orange|Mandarins|Clementines"),
        a("🍋", .produce, "Zitronen|Zitrone|Limetten", "Lemons|Lemon|Limes"),
        a("🍇", .produce, "Trauben|Weintrauben", "Grapes"),
        a("🍓", .produce, "Erdbeeren", "Strawberries"),
        a("🫐", .produce, "Heidelbeeren|Blaubeeren|Beeren|Himbeeren", "Blueberries|Berries|Raspberries"),
        a("🍉", .produce, "Melone|Wassermelone", "Melon|Watermelon"),
        a("🍍", .produce, "Ananas", "Pineapple"),
        a("🥝", .produce, "Kiwis|Kiwi", "Kiwis|Kiwi"),
        a("🥭", .produce, "Mango", "Mango"),
        a("🥑", .produce, "Avocados|Avocado", "Avocados|Avocado"),
        a("🍅", .produce, "Tomaten|Tomate", "Tomatoes|Tomato"),
        a("🥒", .produce, "Gurke|Gurken|Zucchini", "Cucumber|Cucumbers|Zucchini"),
        a("🫑", .produce, "Paprika", "Bell peppers|Peppers"),
        a("🥕", .produce, "Karotten|Möhren|Karotte", "Carrots|Carrot"),
        a("🥔", .produce, "Kartoffeln|Kartoffel", "Potatoes|Potato"),
        a("🧅", .produce, "Zwiebeln|Zwiebel", "Onions|Onion"),
        a("🧄", .produce, "Knoblauch", "Garlic"),
        a("🥦", .produce, "Brokkoli|Blumenkohl", "Broccoli|Cauliflower"),
        a("🥬", .produce, "Salat|Kopfsalat|Spinat|Eisbergsalat", "Lettuce|Salad|Spinach"),
        a("🌽", .produce, "Mais", "Corn"),
        a("🍄", .produce, "Pilze|Champignons", "Mushrooms"),
        a("🌿", .produce, "Kräuter|Petersilie|Basilikum|Schnittlauch", "Herbs|Parsley|Basil|Chives"),
        a("🫚", .produce, "Ingwer", "Ginger"),
        a("🍆", .produce, "Aubergine", "Eggplant|Aubergine"),
        a("🫛", .produce, "Erbsen|Bohnen", "Peas|Green beans"),
        a("🍑", .produce, "Pfirsiche|Pfirsich|Nektarinen|Aprikosen", "Peaches|Peach|Nectarines|Apricots"),
        a("🍒", .produce, "Kirschen", "Cherries"),
        a("🟣", .produce, "Pflaumen|Zwetschgen", "Plums"),
        a("🍈", .produce, "Honigmelone", "Honeydew melon"),
        a("🍊", .produce, "Grapefruit", "Grapefruit"),
        a("🥥", .produce, "Kokosnuss", "Coconut"),
        a("🌴", .produce, "Datteln|Feigen", "Dates|Figs"),
        a("🍅", .produce, "Cocktailtomaten|Kirschtomaten|Rispentomaten", "Cherry tomatoes"),
        a("🧅", .produce, "Frühlingszwiebeln|Lauchzwiebeln|Schalotten|Rote Zwiebeln", "Spring onions|Scallions|Shallots|Red onions"),
        a("🥬", .produce, "Lauch|Porree", "Leek|Leeks"),
        a("🥬", .produce, "Rucola|Feldsalat|Babyspinat|Chicorée|Radicchio|Pak Choi", "Arugula|Rocket|Lamb's lettuce|Baby spinach|Chicory|Radicchio|Bok choy"),
        a("🥬", .produce, "Kohl|Weißkohl|Rotkohl|Wirsing|Grünkohl|Rosenkohl", "Cabbage|Red cabbage|Savoy cabbage|Kale|Brussels sprouts"),
        a("🥬", .produce, "Kohlrabi|Sellerie|Staudensellerie|Knollensellerie|Fenchel", "Kohlrabi|Celery|Celeriac|Fennel"),
        a("🥕", .produce, "Suppengemüse|Suppengrün", "Soup vegetables"),
        a("🔴", .produce, "Radieschen|Rote Bete", "Radishes|Beetroot|Beets"),
        a("🥦", .produce, "Spargel", "Asparagus"),
        a("🎃", .produce, "Kürbis|Hokkaido|Butternut", "Pumpkin|Squash|Butternut squash"),
        a("🍠", .produce, "Süßkartoffeln|Süßkartoffel", "Sweet potatoes|Sweet potato"),
        a("🌶️", .produce, "Chili|Chilischoten|Peperoni|Jalapeños", "Chili|Chilies|Chili peppers|Jalapeños"),
        a("🌿", .produce, "Dill|Koriander|Minze|Rosmarin|Thymian|Salbei|Kresse|Zitronengras", "Dill|Cilantro|Coriander|Mint|Rosemary|Thyme|Sage|Cress|Lemongrass"),
        a("🌱", .produce, "Sprossen", "Sprouts"),
        a("🍄", .produce, "Steinpilze|Shiitake|Kräuterseitlinge", "Porcini|Shiitake|Oyster mushrooms"),
        a("🍓", .produce, "Johannisbeeren|Stachelbeeren|Brombeeren", "Currants|Gooseberries|Blackberries"),
        a("🍋", .produce, "Rhabarber", "Rhubarb"),

        // Brot & Backwaren
        a("🍞", .bakery, "Brot|Toast|Toastbrot", "Bread|Toast"),
        a("🥖", .bakery, "Baguette", "Baguette"),
        a("🥐", .bakery, "Brötchen|Croissants|Semmeln", "Rolls|Bread rolls|Croissants"),
        a("🥨", .bakery, "Brezeln|Breze|Laugenbrezel", "Pretzels"),
        a("🫓", .bakery, "Wraps|Tortillas|Fladenbrot", "Wraps|Tortillas|Flatbread"),
        a("🍰", .bakery, "Kuchen|Torte", "Cake"),
        a("🍞", .bakery, "Vollkornbrot|Roggenbrot|Bauernbrot|Weißbrot|Dinkelbrot", "Whole grain bread|Rye bread|White bread"),
        a("🍔", .bakery, "Burgerbrötchen|Hot-Dog-Brötchen|Buns", "Burger buns|Hot dog buns|Buns"),
        a("🥖", .bakery, "Ciabatta|Focaccia|Kräuterbaguette|Knoblauchbrot", "Ciabatta|Focaccia|Garlic bread"),
        a("🫓", .bakery, "Knäckebrot|Zwieback|Pita|Naan", "Crispbread|Rusks|Pita|Naan"),
        a("🧁", .bakery, "Muffins|Muffin|Berliner|Donuts", "Muffins|Muffin|Doughnuts|Donuts"),

        // Fleisch, Wurst & Fisch
        a("🥩", .meat, "Fleisch|Rindfleisch|Steak|Hackfleisch|Hack", "Meat|Beef|Steak|Ground beef|Minced meat"),
        a("🍗", .meat, "Hähnchen|Hähnchenbrust|Hühnchen|Pute", "Chicken|Chicken breast|Turkey"),
        a("🥓", .meat, "Speck|Schinken|Bacon", "Bacon|Ham"),
        a("🌭", .meat, "Würstchen|Wiener|Bratwurst", "Sausages|Hot dogs"),
        a("🍖", .meat, "Wurst|Aufschnitt|Salami", "Cold cuts|Salami"),
        a("🐟", .meat, "Fisch|Lachs|Thunfisch", "Fish|Salmon|Tuna"),
        a("🦐", .meat, "Garnelen|Shrimps", "Shrimp|Prawns"),
        a("🌱", .meat, "Tofu", "Tofu"),
        a("🍔", .meat, "Burgerpatties|Frikadellen|Buletten", "Burger patties|Meatballs"),
        a("🥩", .meat, "Schnitzel|Gulasch|Schweinefleisch|Kalbfleisch|Lammfleisch", "Schnitzel|Goulash|Pork|Veal|Lamb"),
        a("🍗", .meat, "Hähnchenschenkel|Chicken Wings|Hähnchenflügel|Putenbrust", "Chicken thighs|Chicken wings|Turkey breast"),
        a("🥓", .meat, "Schinkenwürfel|Speckwürfel|Pancetta|Pastrami", "Diced ham|Bacon bits|Pancetta|Pastrami"),
        a("🌭", .meat, "Bockwurst|Weißwurst|Chorizo", "Frankfurters|Chorizo"),
        a("🐟", .meat, "Forelle|Kabeljau|Seelachs|Makrele|Sardinen|Hering", "Trout|Cod|Pollock|Mackerel|Sardines|Herring"),
        a("🦪", .meat, "Muscheln|Miesmuscheln", "Mussels|Clams"),
        a("🌱", .meat, "Fleischersatz|Veggie-Burger|Sojageschnetzeltes|Seitan|Tempeh|Falafel", "Meat substitute|Veggie burger|Seitan|Tempeh|Falafel"),

        // Kühlregal: Milch, Käse, Eier
        a("🥛", .dairy, "Milch|Hafermilch|Sojamilch", "Milk|Oat milk|Soy milk"),
        a("🧈", .dairy, "Butter|Margarine", "Butter|Margarine"),
        a("🧀", .dairy, "Käse|Gouda|Mozzarella|Parmesan|Frischkäse|Feta", "Cheese|Gouda|Mozzarella|Parmesan|Cream cheese|Feta"),
        a("🥚", .dairy, "Eier|Ei", "Eggs|Egg"),
        a("🍶", .dairy, "Joghurt|Quark|Skyr", "Yogurt|Yoghurt|Quark"),
        a("🥛", .dairy, "Sahne|Schmand|Saure Sahne", "Cream|Sour cream"),
        a("🍮", .dairy, "Pudding", "Pudding"),
        a("🥟", .dairy, "Tortellini|Gnocchi", "Tortellini|Gnocchi"),
        a("🧀", .dairy, "Emmentaler|Cheddar|Camembert|Brie|Bergkäse|Ziegenkäse|Schafskäse|Halloumi|Grillkäse|Reibekäse|Ricotta|Mascarpone|Gorgonzola", "Emmental|Cheddar|Camembert|Brie|Goat cheese|Sheep cheese|Halloumi|Grated cheese|Ricotta|Mascarpone|Gorgonzola"),
        a("🥛", .dairy, "Crème fraîche|Schlagsahne|Kochsahne|Sojasahne|Hafersahne|Buttermilch|Kefir", "Crème fraîche|Whipping cream|Cooking cream|Buttermilk|Kefir"),
        a("🍶", .dairy, "Griechischer Joghurt|Magerquark|Hüttenkäse", "Greek yogurt|Cottage cheese"),
        a("🥛", .dairy, "Kondensmilch|H-Milch|Kakaomilch|Schokomilch", "Condensed milk|UHT milk|Chocolate milk"),
        a("🫙", .dairy, "Hummus|Tzatziki|Aioli|Guacamole|Obatzda", "Hummus|Tzatziki|Aioli|Guacamole"),
        a("🥐", .dairy, "Blätterteig|Pizzateig|Hefeteig|Mürbeteig|Croissantteig", "Puff pastry|Pizza dough|Dough"),
        a("🍝", .dairy, "Spätzle|Maultaschen|Schupfnudeln|Frische Pasta", "Spaetzle|Fresh pasta"),
        a("🥚", .dairy, "Eiersalat", "Egg salad"),

        // Grundnahrungsmittel, Konserven, Gewürze
        a("🍝", .pantry, "Nudeln|Spaghetti|Pasta|Penne", "Pasta|Spaghetti|Noodles|Penne"),
        a("🍚", .pantry, "Reis", "Rice"),
        a("🌾", .pantry, "Mehl", "Flour"),
        a("🧂", .pantry, "Salz|Pfeffer|Gewürze", "Salt|Pepper|Spices"),
        a("🍬", .pantry, "Zucker", "Sugar"),
        a("🫒", .pantry, "Öl|Olivenöl|Sonnenblumenöl|Oliven", "Oil|Olive oil|Olives"),
        a("🍾", .pantry, "Essig", "Vinegar"),
        a("🥫", .pantry, "Dosentomaten|Passata|Tomatenmark|Konserven|Mais in der Dose", "Canned tomatoes|Passata|Tomato paste|Canned food"),
        a("🫘", .pantry, "Kidneybohnen|Linsen|Kichererbsen", "Kidney beans|Lentils|Chickpeas"),
        a("🍅", .pantry, "Ketchup", "Ketchup"),
        a("🟡", .pantry, "Senf|Mayonnaise|Mayo", "Mustard|Mayonnaise|Mayo"),
        a("🥣", .pantry, "Brühe|Suppe|Gemüsebrühe", "Broth|Stock|Soup"),
        a("🧁", .pantry, "Backpulver|Hefe|Vanillezucker", "Baking powder|Yeast|Vanilla sugar"),
        a("🫙", .pantry, "Soße|Pesto|Sojasoße", "Sauce|Pesto|Soy sauce"),
        a("🪵", .pantry, "Zimt|Zimtstangen", "Cinnamon|Cinnamon sticks"),
        a("🌿", .pantry, "Oregano|Majoran|Basilikum getrocknet|Italienische Kräuter|Kräuter der Provence|Lorbeerblätter|Lorbeer|Getrocknete Kräuter", "Oregano|Marjoram|Dried basil|Italian herbs|Herbes de Provence|Bay leaves|Dried herbs"),
        a("🌶️", .pantry, "Paprikapulver|Paprika edelsüß|Paprika rosenscharf|Chilipulver|Chiliflocken|Cayennepfeffer|Geräuchertes Paprikapulver", "Paprika powder|Smoked paprika|Chili powder|Chili flakes|Cayenne pepper"),
        a("🧂", .pantry, "Curry|Currypulver|Kurkuma|Kreuzkümmel|Kümmel|Koriandersamen|Garam Masala|Kardamom|Muskat|Muskatnuss|Nelken|Gewürznelken|Ingwerpulver|Knoblauchpulver|Zwiebelpulver|Safran|Sternanis|Anis", "Curry powder|Turmeric|Cumin|Caraway|Coriander seeds|Garam masala|Cardamom|Nutmeg|Cloves|Ground ginger|Garlic powder|Onion powder|Saffron|Star anise|Anise"),
        a("🧂", .pantry, "Meersalz|Pfefferkörner|Zitronenpfeffer|Gewürzmischung|Grillgewürz", "Sea salt|Peppercorns|Lemon pepper|Seasoning|BBQ rub"),
        a("🌼", .pantry, "Vanille|Vanilleschote|Vanilleextrakt|Bourbon-Vanille", "Vanilla|Vanilla pod|Vanilla extract"),
        a("🍬", .pantry, "Puderzucker|Brauner Zucker|Rohrzucker|Gelierzucker|Süßstoff", "Powdered sugar|Icing sugar|Brown sugar|Cane sugar|Jam sugar|Sweetener"),
        a("🧁", .pantry, "Natron|Trockenhefe|Speisestärke|Gelatine|Agar-Agar|Lebensmittelfarbe|Streusel|Kuvertüre|Kuchenglasur|Backmischung", "Baking soda|Dry yeast|Cornstarch|Gelatin|Agar|Food coloring|Sprinkles|Couverture|Icing|Cake mix"),
        a("🌾", .pantry, "Weizenmehl|Dinkelmehl|Vollkornmehl|Paniermehl|Semmelbrösel|Grieß|Polenta", "Wheat flour|Spelt flour|Whole wheat flour|Breadcrumbs|Semolina|Polenta"),
        a("🍫", .pantry, "Backkakao|Schokotropfen|Blockschokolade", "Baking cocoa|Chocolate chips|Baking chocolate"),
        a("🥥", .pantry, "Kokosraspeln|Kokosmilch|Kokosöl", "Desiccated coconut|Coconut milk|Coconut oil"),
        a("🥜", .pantry, "Haselnüsse gemahlen|Mandeln gemahlen|Pinienkerne|Sonnenblumenkerne|Kürbiskerne|Sesam|Leinsamen|Chiasamen|Walnüsse|Cashews|Pekannüsse", "Ground hazelnuts|Ground almonds|Pine nuts|Sunflower seeds|Pumpkin seeds|Sesame|Flaxseed|Chia seeds|Walnuts|Cashews|Pecans"),
        a("🍇", .pantry, "Rosinen|Trockenobst|Cranberries getrocknet|Marzipan", "Raisins|Dried fruit|Dried cranberries|Marzipan"),
        a("🫒", .pantry, "Rapsöl|Sesamöl|Bratöl|Speiseöl|Pflanzenöl", "Canola oil|Rapeseed oil|Sesame oil|Cooking oil|Vegetable oil"),
        a("🍾", .pantry, "Balsamico|Apfelessig|Weißweinessig|Rotweinessig|Reisessig", "Balsamic vinegar|Apple cider vinegar|White wine vinegar|Red wine vinegar|Rice vinegar"),
        a("🌶️", .pantry, "Sriracha|Tabasco|Sambal Oelek|Harissa|Sweet-Chili-Soße|Chilisoße", "Sriracha|Tabasco|Sambal oelek|Harissa|Sweet chili sauce|Hot sauce"),
        a("🫙", .pantry, "Currypaste|Misopaste|Tahini|Worcestersoße|Teriyaki|Grillsoße|Barbecuesoße|Salatdressing|Dressing|Nudelsoße|Tomatensoße|Fischsoße|Maggi", "Curry paste|Miso paste|Tahini|Worcestershire sauce|Teriyaki|BBQ sauce|Salad dressing|Dressing|Pasta sauce|Tomato sauce|Fish sauce"),
        a("🍯", .pantry, "Ahornsirup|Agavendicksaft|Sirup", "Maple syrup|Agave syrup|Syrup"),
        a("🍋", .pantry, "Zitronensaft", "Lemon juice"),
        a("🥫", .pantry, "Gehackte Tomaten|Stückige Tomaten|Passierte Tomaten|Getrocknete Tomaten|Dosensuppe|Ravioli in der Dose", "Chopped tomatoes|Crushed tomatoes|Sun-dried tomatoes|Canned soup|Canned ravioli"),
        a("🥒", .pantry, "Gewürzgurken|Essiggurken|Saure Gurken|Kapern|Sauerkraut|Rotkohl im Glas|Kimchi", "Pickles|Gherkins|Capers|Sauerkraut|Kimchi"),
        a("🫘", .pantry, "Weiße Bohnen|Schwarze Bohnen|Rote Linsen|Baked Beans|Bohnen in der Dose", "White beans|Black beans|Red lentils|Baked beans|Canned beans"),
        a("🐟", .pantry, "Thunfisch in der Dose|Sardinen in der Dose", "Canned tuna|Canned sardines"),
        a("🍍", .pantry, "Ananas in der Dose|Mandarinen in der Dose|Pfirsiche in der Dose|Apfelmus|Kompott", "Canned pineapple|Canned mandarins|Canned peaches|Applesauce|Compote"),
        a("🍝", .pantry, "Fusilli|Farfalle|Makkaroni|Tagliatelle|Bandnudeln|Lasagneplatten|Lasagne|Linguine|Rigatoni|Spätzle getrocknet", "Fusilli|Farfalle|Macaroni|Tagliatelle|Lasagna sheets|Lasagna|Linguine|Rigatoni"),
        a("🍜", .pantry, "Reisnudeln|Glasnudeln|Mie-Nudeln|Eiernudeln|Ramen|Udon|Soba|Instantnudeln|Fünf-Minuten-Terrine", "Rice noodles|Glass noodles|Egg noodles|Ramen|Udon|Soba|Instant noodles|Cup noodles"),
        a("🍚", .pantry, "Basmatireis|Jasminreis|Risottoreis|Milchreis|Sushireis|Vollkornreis|Wildreis", "Basmati rice|Jasmine rice|Risotto rice|Rice pudding|Sushi rice|Brown rice|Wild rice"),
        a("🌾", .pantry, "Couscous|Bulgur|Quinoa|Hirse|Graupen", "Couscous|Bulgur|Quinoa|Millet|Pearl barley"),
        a("🍙", .pantry, "Reispapier|Noriblätter|Algen", "Rice paper|Nori|Seaweed"),
        a("🥔", .pantry, "Kartoffelpüree|Kartoffelpüreepulver|Knödel|Klöße|Kartoffelknödel|Semmelknödel", "Mashed potato mix|Potato dumplings|Bread dumplings"),
        a("🥣", .pantry, "Brühwürfel|Hühnerbrühe|Rinderbrühe|Fond", "Stock cubes|Bouillon cubes|Chicken stock|Beef stock"),
        a("🌮", .pantry, "Tacos|Taco-Schalen|Nachos|Tortilla-Chips|Fajita-Gewürz", "Taco shells|Tacos|Nachos|Tortilla chips|Fajita seasoning"),

        // Frühstück
        a("🥣", .breakfast, "Müsli|Cornflakes|Haferflocken|Cerealien", "Muesli|Cereal|Cornflakes|Oats|Rolled oats"),
        a("🍓", .breakfast, "Marmelade|Konfitüre", "Jam"),
        a("🍯", .breakfast, "Honig", "Honey"),
        a("🍫", .breakfast, "Nutella|Schokocreme|Nougatcreme", "Nutella|Chocolate spread"),
        a("🥜", .breakfast, "Erdnussbutter", "Peanut butter"),
        a("☕️", .breakfast, "Kaffee|Kaffeebohnen|Kaffeepads|Kapseln", "Coffee|Coffee beans|Coffee pods"),
        a("🫖", .breakfast, "Tee", "Tea"),
        a("🍫", .breakfast, "Kakao|Kakaopulver", "Cocoa|Hot chocolate"),
        a("🥣", .breakfast, "Porridge|Granola|Knuspermüsli|Schokomüsli|Overnight Oats", "Porridge|Granola|Crunchy muesli"),
        a("🍫", .breakfast, "Schokoaufstrich|Brotaufstrich|Aufstrich", "Spread"),
        a("🍋", .breakfast, "Lemon Curd", "Lemon curd"),
        a("☕️", .breakfast, "Espresso|Kaffeepulver|Filterkaffee|Löslicher Kaffee|Instantkaffee|Kaffeefilter", "Espresso|Ground coffee|Instant coffee|Coffee filters"),
        a("🫖", .breakfast, "Früchtetee|Kräutertee|Grüner Tee|Schwarzer Tee|Pfefferminztee|Kamillentee", "Fruit tea|Herbal tea|Green tea|Black tea|Peppermint tea|Chamomile tea"),
        a("🥛", .breakfast, "Kaffeesahne|Kaffeeweißer|Barista-Milch", "Coffee creamer|Creamer"),

        // Süßes & Snacks
        a("🍫", .snacks, "Schokolade", "Chocolate"),
        a("🍪", .snacks, "Kekse|Plätzchen", "Cookies|Biscuits"),
        a("🍬", .snacks, "Gummibärchen|Süßigkeiten|Bonbons", "Gummy bears|Candy|Sweets"),
        a("🥔", .snacks, "Chips", "Chips|Crisps"),
        a("🥨", .snacks, "Salzstangen|Knabberzeug", "Pretzel sticks|Snacks"),
        a("🥜", .snacks, "Nüsse|Erdnüsse|Mandeln", "Nuts|Peanuts|Almonds"),
        a("🍿", .snacks, "Popcorn", "Popcorn"),
        a("🍦", .snacks, "Eis|Eiscreme", "Ice cream"),
        a("🍪", .snacks, "Butterkekse|Löffelbiskuits|Waffeln|Lebkuchen|Spekulatius|Reiswaffeln|Maiswaffeln", "Butter biscuits|Ladyfingers|Wafers|Gingerbread|Speculoos|Rice cakes|Corn cakes"),
        a("🍬", .snacks, "Fruchtgummi|Lakritz|Kaugummi|Marshmallows|Hustenbonbons|Lutscher", "Fruit gums|Licorice|Chewing gum|Marshmallows|Cough drops|Lollipops"),
        a("🍫", .snacks, "Schokoriegel|Pralinen|Weiße Schokolade|Zartbitterschokolade", "Chocolate bars|Pralines|White chocolate|Dark chocolate"),
        a("🥣", .snacks, "Müsliriegel|Proteinriegel", "Granola bars|Cereal bars|Protein bars"),
        a("🥜", .snacks, "Erdnussflips|Studentenfutter|Cashewkerne|Pistazien", "Peanut puffs|Trail mix|Cashew nuts|Pistachios"),
        a("🥨", .snacks, "Cracker|Kräcker|Käsecracker", "Crackers|Cheese crackers"),

        // Getränke
        a("💧", .drinks, "Wasser|Mineralwasser|Sprudel", "Water|Mineral water|Sparkling water"),
        a("🧃", .drinks, "Saft|Apfelsaft|Orangensaft|Schorle", "Juice|Apple juice|Orange juice"),
        a("🥤", .drinks, "Cola|Limo|Limonade|Eistee", "Cola|Soda|Lemonade|Iced tea"),
        a("🍺", .drinks, "Bier", "Beer"),
        a("🍷", .drinks, "Wein|Rotwein|Weißwein", "Wine|Red wine|White wine"),
        a("🥂", .drinks, "Sekt|Prosecco|Champagner", "Sparkling wine|Prosecco|Champagne"),
        a("🥤", .drinks, "Fanta|Sprite|Spezi|Ginger Ale|Tonic Water|Bitter Lemon|Energydrink|Red Bull|Mate", "Fanta|Sprite|Ginger ale|Tonic water|Bitter lemon|Energy drink|Red Bull|Club-Mate"),
        a("🧃", .drinks, "Multivitaminsaft|Traubensaft|Tomatensaft|Smoothie|Nektar|Sirup für Getränke|Himbeersirup", "Multivitamin juice|Grape juice|Tomato juice|Smoothie|Nectar|Cordial"),
        a("🍺", .drinks, "Pils|Radler|Weizenbier|Alkoholfreies Bier|Cider|Apfelwein", "Lager|Shandy|Wheat beer|Alcohol-free beer|Cider"),
        a("🍸", .drinks, "Gin|Wodka|Whisky|Likör|Aperol|Lillet|Schnaps|Spirituosen|Glühwein|Eierlikör", "Gin|Vodka|Whisky|Whiskey|Liqueur|Aperol|Lillet|Spirits|Mulled wine|Eggnog"),
        a("🥛", .drinks, "Hafer Drink|Haferdrink|Mandeldrink|Mandelmilch|Reisdrink|Sojadrink", "Oat drink|Almond milk|Almond drink|Rice milk|Soy drink"),

        // Tiefkühl
        a("🍕", .frozen, "Pizza|Tiefkühlpizza", "Pizza|Frozen pizza"),
        a("🍟", .frozen, "Pommes", "Fries|French fries"),
        a("🥦", .frozen, "Tiefkühlgemüse|TK-Gemüse", "Frozen vegetables"),
        a("🐟", .frozen, "Fischstäbchen", "Fish fingers|Fish sticks"),
        a("🧊", .frozen, "Eiswürfel", "Ice cubes"),
        a("🥬", .frozen, "TK-Spinat|Rahmspinat|TK-Erbsen|TK-Kräuter|TK-Brokkoli|Edamame", "Frozen spinach|Creamed spinach|Frozen peas|Frozen herbs|Edamame"),
        a("🍓", .frozen, "TK-Beeren|TK-Obst|Tiefkühlobst", "Frozen berries|Frozen fruit"),
        a("🍟", .frozen, "Kartoffelecken|Wedges|Kroketten|Rösti|Ofenkartoffeln", "Potato wedges|Croquettes|Hash browns"),
        a("🐟", .frozen, "Backfisch|Schlemmerfilet|Tiefkühlfisch", "Battered fish|Frozen fish"),
        a("🍗", .frozen, "Chicken Nuggets|Nuggets|Cordon bleu", "Chicken nuggets|Nuggets"),
        a("🥟", .frozen, "Dumplings|Gyoza|Frühlingsrollen|Baguettebrötchen zum Aufbacken|Aufbackbrötchen", "Dumplings|Gyoza|Spring rolls|Bake-off rolls"),
        a("🍧", .frozen, "Wassereis|Sorbet|Eis am Stiel|Mochi", "Ice pops|Sorbet|Popsicles|Mochi"),
        a("🍕", .frozen, "Flammkuchen|Lasagne TK|Fertiggericht", "Tarte flambée|Ready meal|Frozen meal"),

        // Haushalt
        a("🧻", .household, "Toilettenpapier|Klopapier", "Toilet paper"),
        a("🧻", .household, "Küchenrolle|Küchenpapier", "Paper towels|Kitchen roll"),
        a("🧽", .household, "Schwämme|Spülschwamm", "Sponges"),
        a("🫧", .household, "Spülmittel|Spülmaschinentabs|Tabs", "Dish soap|Dishwasher tabs"),
        a("🧺", .household, "Waschmittel|Weichspüler", "Laundry detergent|Fabric softener"),
        a("🗑️", .household, "Müllbeutel|Mülltüten", "Trash bags|Bin bags"),
        a("🧼", .household, "Putzmittel|Reiniger|Allzweckreiniger", "Cleaner|Cleaning spray"),
        a("📦", .household, "Alufolie|Frischhaltefolie|Backpapier|Gefrierbeutel", "Aluminum foil|Cling film|Baking paper|Freezer bags"),
        a("🔋", .household, "Batterien", "Batteries"),
        a("💡", .household, "Glühbirne|Leuchtmittel", "Light bulb|Light bulbs"),
        a("🕯️", .household, "Kerzen|Teelichter", "Candles|Tea lights"),
        a("🌸", .household, "Blumen", "Flowers"),
        a("🧽", .household, "Schwammtücher|Spültücher|Mikrofasertücher|Putzlappen|Wischtücher", "Sponge cloths|Dishcloths|Microfiber cloths|Cleaning cloths"),
        a("🫧", .household, "Geschirrspülmittel|Spüli|Klarspüler|Spülmaschinensalz|Regeneriersalz|Maschinenpfleger", "Dishwashing liquid|Rinse aid|Dishwasher salt|Machine cleaner"),
        a("🧺", .household, "Waschpulver|Colorwaschmittel|Feinwaschmittel|Fleckentferner|Hygienespüler|Waschmittelblätter", "Washing powder|Color detergent|Delicate detergent|Stain remover|Laundry sanitizer|Laundry sheets"),
        a("🧼", .household, "WC-Reiniger|Badreiniger|Glasreiniger|Entkalker|Schimmelentferner|Desinfektionsmittel|Desinfektionsspray|Scheuermilch|Bodenreiniger", "Toilet cleaner|Bathroom cleaner|Glass cleaner|Descaler|Mould remover|Disinfectant|Floor cleaner"),
        a("🗑️", .household, "Biomüllbeutel|Gelbe Säcke|Staubsaugerbeutel", "Compost bags|Recycling bags|Vacuum bags"),
        a("🧻", .household, "Servietten|Taschentuchbox", "Napkins|Tissue box"),
        a("📦", .household, "Butterbrotpapier|Muffinförmchen|Zahnstocher|Strohhalme|Pappteller|Pappbecher", "Sandwich paper|Muffin cases|Toothpicks|Straws|Paper plates|Paper cups"),
        a("🔥", .household, "Streichhölzer|Feuerzeug|Grillkohle|Anzünder", "Matches|Lighter|Charcoal|Fire starters"),
        a("🔋", .household, "Knopfzellen|Akkus", "Button cells|Rechargeable batteries"),
        a("🩹", .household, "Klebeband|Tesafilm|Paketband", "Tape|Sticky tape|Packing tape"),
        a("🎁", .household, "Geschenkpapier|Geburtstagskarte|Glückwunschkarte|Karte", "Wrapping paper|Birthday card|Greeting card|Card"),
        a("🪴", .household, "Blumenerde|Dünger|Pflanzen", "Potting soil|Fertilizer|Plants"),

        // Drogerie
        a("🪥", .hygiene, "Zahnpasta|Zahnbürste|Zahnseide", "Toothpaste|Toothbrush|Floss"),
        a("🧴", .hygiene, "Duschgel|Shampoo|Spülung|Bodylotion|Creme", "Shower gel|Shampoo|Conditioner|Body lotion|Lotion"),
        a("🧼", .hygiene, "Seife|Handseife", "Soap|Hand soap"),
        a("🪒", .hygiene, "Rasierer|Rasierklingen|Rasierschaum", "Razor|Razor blades|Shaving foam"),
        a("🧻", .hygiene, "Taschentücher", "Tissues"),
        a("🌸", .hygiene, "Deo|Deodorant", "Deodorant"),
        a("🩹", .hygiene, "Pflaster", "Band-aids|Plasters"),
        a("💊", .hygiene, "Medikamente|Schmerztabletten|Ibuprofen|Paracetamol", "Medicine|Painkillers|Ibuprofen|Paracetamol"),
        a("🌞", .hygiene, "Sonnencreme", "Sunscreen"),
        a("🩸", .hygiene, "Tampons|Binden", "Tampons|Pads"),
        a("🧽", .hygiene, "Wattepads|Wattestäbchen", "Cotton pads|Cotton buds"),
        a("🫧", .hygiene, "Flüssigseife|Waschgel|Gesichtsreinigung|Abschminktücher", "Liquid soap|Face wash|Cleanser|Makeup wipes"),
        a("🧴", .hygiene, "Gesichtscreme|Feuchtigkeitscreme|Handcreme|Lippenpflege|Labello|Haarspülung|Haargel|Haarspray|Haarwachs", "Face cream|Moisturizer|Hand cream|Lip balm|Hair conditioner|Hair gel|Hairspray|Hair wax"),
        a("🪥", .hygiene, "Mundspülung|Zahnbürstenköpfe|Interdentalbürsten|Zahnseide-Sticks", "Mouthwash|Toothbrush heads|Interdental brushes|Floss picks"),
        a("💄", .hygiene, "Make-up|Mascara|Wimperntusche|Lippenstift|Concealer|Nagellack|Nagellackentferner|Nagelfeile", "Makeup|Mascara|Lipstick|Concealer|Nail polish|Nail polish remover|Nail file"),
        a("🎀", .hygiene, "Haargummis|Haarspangen|Haarbürste|Kamm", "Hair ties|Hair clips|Hairbrush|Comb"),
        a("🩸", .hygiene, "Slipeinlagen|Menstruationstasse", "Panty liners|Menstrual cup"),
        a("💊", .hygiene, "Aspirin|Nasenspray|Hustensaft|Hustensirup|Halstabletten|Vitamine|Vitamintabletten|Magnesium|Fieberthermometer|Schnelltest", "Aspirin|Nasal spray|Cough syrup|Throat lozenges|Vitamins|Magnesium|Thermometer|Rapid test"),
        a("🩹", .hygiene, "Blasenpflaster|Verband|Mullbinden|Desinfektionsspray für Wunden|Wundsalbe", "Blister plasters|Bandage|Gauze|Wound spray|Wound ointment"),
        a("😷", .hygiene, "Masken|FFP2-Masken|Mundschutz", "Masks|Face masks|FFP2 masks"),
        a("🦟", .hygiene, "Mückenspray|Mückenschutz|Zeckenzange", "Insect repellent|Mosquito spray|Tick remover"),

        // Baby
        a("🧷", .baby, "Windeln|Pampers|Schwimmwindeln|Pants", "Diapers|Nappies|Swim diapers"),
        a("🫧", .baby, "Feuchttücher|Feuchte Tücher|Babytücher", "Wet wipes|Baby wipes"),
        a("🧴", .baby, "Wundschutzcreme|Zinksalbe|Babyöl|Babyshampoo|Babycreme", "Diaper cream|Zinc cream|Baby oil|Baby shampoo|Baby lotion"),
        a("🍼", .baby, "Fläschchen|Sauger|Schnuller|Beruhigungssauger", "Baby bottles|Teats|Pacifier|Dummy"),
        a("🍐", .baby, "Quetschies|Quetschbeutel|Gläschen|Breigläschen|Babykekse|Hirsebrei|Getreidebrei", "Fruit pouches|Pouches|Baby jars|Baby biscuits|Baby cereal"),
        a("🍼", .baby, "Babynahrung|Babybrei|Milchpulver", "Baby food|Formula"),

        // Tierbedarf
        a("🐱", .pets, "Katzenfutter|Katzenstreu", "Cat food|Cat litter"),
        a("🐶", .pets, "Hundefutter|Leckerlis", "Dog food|Dog treats"),
        a("🐾", .pets, "Katzenleckerlis|Kauknochen|Kotbeutel|Hundekotbeutel|Tierfutter", "Cat treats|Chews|Poop bags|Pet food"),
        a("🐦", .pets, "Vogelfutter|Meisenknödel", "Bird seed|Fat balls"),
        a("🐠", .pets, "Fischfutter", "Fish food"),
    ]
}
