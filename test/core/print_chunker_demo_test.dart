import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/core/chunker/text_chunker.dart';

void main() {
  test('Print realistic chunker output for English, Hindi, and Kannada', () {
    const chunker = TextChunker();

    const englishParagraph = '''
Mitochondria are membrane-bound cell organelles that generate most of the chemical energy needed to power the biochemical reactions of the cell.
Chemical energy produced by the mitochondria is stored in a small molecule called adenosine triphosphate, or ATP.
Mitochondria contain their own small chromosomes, and generally, genes are inherited only from the mother.
During cellular respiration, glucose and oxygen are converted into carbon dioxide, water, and ATP.
This process begins in the cytoplasm with glycolysis, breaking down one molecule of glucose into two molecules of pyruvate.
Pyruvate then enters the mitochondrial matrix, where it is converted into acetyl-CoA for the citric acid cycle.
The citric acid cycle produces electron carriers, specifically NADH and FADH2, which proceed to the electron transport chain.
As electrons move down the respiratory chain, protons are pumped across the inner mitochondrial membrane into the intermembrane space.
This generates an electrochemical proton gradient across the inner membrane, which drives ATP synthase.
Finally, oxygen acts as the terminal electron acceptor, combining with free protons to produce harmless water molecules.
Without functional mitochondria, complex multicellular life would be unable to sustain the massive energetic requirements of animal tissues.
''';

    const hindiParagraph = '''
प्रकाश संश्लेषण एक ऐसी जैविक प्रक्रिया है जिसके द्वारा हरे पौधे सूर्य के प्रकाश की ऊर्जा को रासायनिक ऊर्जा में परिवर्तित करते हैं।
इस प्रक्रिया में पौधे वायुमंडल से कार्बन डाइऑक्साइड और मिट्टी से जल अवशोषित करते हैं।
सूर्य के प्रकाश की उपस्थिति में क्लोरोफिल की सहायता से ग्लूकोज और ऑक्सीजन का निर्माण होता है।
यह संपूर्ण अभिक्रिया मुख्य रूप से पादप कोशिकाओं के क्लोरोप्लास्ट में संपन्न होती है।
क्लोरोप्लास्ट के भीतर थाइलाकोइड झिल्ली में प्रकाश रासायनिक अभिक्रियाएं घटित होती हैं, जिन्हें प्रकाश-निर्भर अभिक्रियाएं कहा जाता है।
इस चरण में जल के अणुओं का प्रकाशिक अपघटन होता है, जिससे ऑक्सीजन गैस मुक्त होकर वायुमंडल में फैल जाती है।
इसके साथ ही उच्च ऊर्जा वाले रासायनिक अणु जैसे एटीपी और एनएडीपीएच का संश्लेषण होता है।
दूसरा मुख्य चरण स्ट्रोमा में संपन्न होता है, जिसे केल्विन चक्र या प्रकाश-अंधकार अभिक्रिया के रूप में जाना जाता है।
केल्विन चक्र में कार्बन डाइऑक्साइड का स्थिरीकरण होकर कार्बोहाइड्रेट अथवा शर्करा का निर्माण होता है।
यह उत्पादित शर्करा पौधों की वृद्धि, ऊर्जा और श्वसन के लिए आवश्यक प्राथमिक पोषण प्रदान करती है।
अतः पृथ्वी पर समस्त जीव जगत के अस्तित्व और जीवन यापन के लिए प्रकाश संश्लेषण की क्रिया अत्यंत अनिवार्य है।
''';

    const kannadaParagraph = '''
ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆಯು ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕಿನ ಶಕ್ತಿಯನ್ನು ರಾಸಾಯನಿಕ ಶಕ್ತಿಯನ್ನಾಗಿ ಪರಿವರ್ತಿಸುವ ಒಂದು ಪ್ರಮುಖ ಜೈವಿಕ ಪ್ರಕ್ರಿಯೆಯಾಗಿದೆ.
ಈ ಕ್ರಿಯೆಯಲ್ಲಿ ಹಸಿರು ಸಸ್ಯಗಳು ವಾತಾವರಣದಿಂದ ಇಂಗಾಲದ ಡೈಆಕ್ಸೈಡ್ ಅನ್ನು ಮತ್ತು ಭೂಮಿಯಿಂದ ನೀರನ್ನು ಹೀರಿಕೊಳ್ಳುತ್ತವೆ.
ಎಲೆಗಳಲ್ಲಿರುವ ಹರಿತ್ತು ಅಥವಾ ಕ್ಲೋರೋಫಿಲ್ ಸೂರ್ಯನ ಕಿರಣಗಳನ್ನು ಹೀರಿಕೊಂಡು ಈ ರಾಸಾಯನಿಕ ಪ್ರಕ್ರಿಯೆಯನ್ನು ಆರಂಭಿಸುತ್ತದೆ.
ಈ ಕ್ರಿಯೆಯ ಫಲವಾಗಿ ಸಸ್ಯಗಳು ತಮಗೆ ಅಗತ್ಯವಾದ ಗ್ಲೂಕೋಸ್ ಮತ್ತು ಮಾನವಕುಲಕ್ಕೆ ಜೀವ ನೀಡುವ ಆಮ್ಲಜನಕವನ್ನು ಬಿಡುಗಡೆ ಮಾಡುತ್ತವೆ.
ಸಸ್ಯ ಕೋಶಗಳಲ್ಲಿರುವ ಹರಿದ್ರೇಣು ಅಥವಾ ಕ್ಲೋರೋಪ್ಲಾಸ್ಟ್ ಒಳಗೆ ಈ ಎಲ್ಲಾ ಜೀವ ರಾಸಾಯನಿಕ ಕ್ರಿಯೆಗಳು ನಡೆಯುತ್ತವೆ.
ಬೆಳಕಿನ ಅವಲಂಬಿತ ಕ್ರಿಯೆಗಳು ಥೈಲಾಕಾಯ್ಡ್ ಪದರಗಳಲ್ಲಿ ನಡೆದು ನೀರಿನ ಕಣಗಳನ್ನು ವಿಭಜಿಸುತ್ತವೆ.
ನೀರಿನ ವಿಭಜನೆಯಿಂದಾಗಿ ಆಮ್ಲಜನಕ ಅನಿಲವು ಬಿಡುಗಡೆಯಾಗಿ ವಾತಾವರಣವನ್ನು ಸೇರುತ್ತದೆ.
ಅದೇ ಸಮಯದಲ್ಲಿ ಎಟಿಪಿ ಮತ್ತು ಎನ್‌ಎಡಿಪಿಎಚ್‌ನಂತಹ ಶಕ್ತಿಯುತ ಅಣುಗಳು ಈ ಹಂತದಲ್ಲಿ ಉತ್ಪತ್ತಿಯಾಗುತ್ತವೆ.
ಬೆಳಕಿನ ಅಗತ್ಯವಿಲ್ಲದ ಕೆಲ್ವಿನ್ ಚಕ್ರವು ಹರಿದ್ರೇಣುವಿನ ಸ್ಟ್ರೋಮಾದಲ್ಲಿ ಜರುಗಿ ಗ್ಲೂಕೋಸ್ ಅನ್ನು ಸಂಶ್ಲೇಷಿಸುತ್ತದೆ.
ಉತ್ಪತ್ತಿಯಾದ ಆಹಾರವು ಸಸ್ಯಗಳ ಬೆಳವಣಿಗೆಗೆ, ಜೀವಕೋಶಗಳ ದುರಸ್ತಿಗೆ ಮತ್ತು ಮುಂದಿನ ಬಳಕೆಗಾಗಿ ಶೇಖರಣೆಯಾಗುತ್ತದೆ.
ಭೂಮಿಯ ಮೇಲಿನ ಸಮಸ್ತ ಜೀವರಾಶಿಯ ಉಳಿವು ಮತ್ತು ಆಹಾರ ಸರಪಳಿಯ ಸಮತೋಲನಕ್ಕೆ ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆ ಅತ್ಯಂತ ಅನಿವಾರ್ಯವಾಗಿದೆ.
''';

    print('\n==================== ENGLISH CHUNKS ====================');
    final enChunks = chunker.chunk(englishParagraph);
    for (final c in enChunks) {
      print('[#${c.index.toString().padLeft(2, '0')}] (${c.wordCount} words | ${c.boundaryType.name.padRight(9)}): "${c.text}"');
    }

    print('\n==================== HINDI CHUNKS ====================');
    final hiChunks = chunker.chunk(hindiParagraph);
    for (final c in hiChunks) {
      print('[#${c.index.toString().padLeft(2, '0')}] (${c.wordCount} words | ${c.boundaryType.name.padRight(9)}): "${c.text}"');
    }

    print('\n==================== KANNADA CHUNKS ====================');
    final knChunks = chunker.chunk(kannadaParagraph);
    for (final c in knChunks) {
      print('[#${c.index.toString().padLeft(2, '0')}] (${c.wordCount} words | ${c.boundaryType.name.padRight(9)}): "${c.text}"');
    }

    expect(enChunks, isNotEmpty);
    expect(hiChunks, isNotEmpty);
    expect(knChunks, isNotEmpty);
  });
}
