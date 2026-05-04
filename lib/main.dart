import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' hide context; // 에러 해결: path 패키지의 context 이름 충돌 방지
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

// 외부 기능 패키지
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// ==========================================
// 1. 데이터 모델 (Word)
// ==========================================
enum Difficulty { again, hard, good, easy }

class Word {
  final int? id;
  final String word;
  final String meaning;
  String? sentence;
  String? translation;
  int interval;
  double easeFactor;
  DateTime nextReview;
  int isLearned;

  Word({
    this.id,
    required this.word,
    required this.meaning,
    this.sentence,
    this.translation,
    this.interval = 0,
    this.easeFactor = 2.5,
    DateTime? nextReview,
    this.isLearned = 0,
  }) : this.nextReview = nextReview ?? DateTime.now();

  bool get needsAiExample => sentence == null || sentence!.isEmpty;

  // 빈칸 뚫기 (말해보카 스타일)
  String get maskedSentence {
    if (sentence == null || sentence!.isEmpty) return "...";
    final regex = RegExp(r'\b' + word + r'\b', caseSensitive: false);
    return sentence!.replaceAll(regex, "____");
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word': word,
      'meaning': meaning,
      'sentence': sentence,
      'translation': translation,
      'interval': interval,
      'easeFactor': easeFactor,
      'nextReview': nextReview.toIso8601String(),
      'isLearned': isLearned,
    };
  }

  factory Word.fromMap(Map<String, dynamic> map) {
    return Word(
      id: map['id'],
      word: map['word'],
      meaning: map['meaning'],
      sentence: map['sentence'],
      translation: map['translation'],
      interval: map['interval'] ?? 0,
      easeFactor: (map['easeFactor'] as num?)?.toDouble() ?? 2.5,
      nextReview: DateTime.parse(map['nextReview'] ?? DateTime.now().toIso8601String()),
      isLearned: map['isLearned'] ?? 0,
    );
  }

  void processReview(Difficulty difficulty) {
    int quality = 3;
    if (difficulty == Difficulty.again) quality = 0;
    else if (difficulty == Difficulty.hard) quality = 3;
    else if (difficulty == Difficulty.good) quality = 4;
    else if (difficulty == Difficulty.easy) quality = 5;

    easeFactor = easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (easeFactor < 1.3) easeFactor = 1.3;

    if (quality < 3) {
      interval = 1;
    } else {
      if (interval == 0) interval = 1;
      else if (interval == 1) interval = 6;
      else interval = (interval * easeFactor).round();
    }
    nextReview = DateTime.now().add(Duration(days: interval));
    isLearned = 1;
  }
}

// ==========================================
// 2. 서비스 (Gemini API & 공용 저장소)
// ==========================================
class ApiService {
  final String apiKey = const String.fromEnvironment('GEMINI_API_KEY');

  Future<Map<String, String>?> fetchExample(String word) async {
    if (apiKey.isEmpty) return null;
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      // 일상 회화 예문을 만들도록 지시
      final prompt = "You are an English teacher. Create a highly natural, conversational example sentence used in everyday life, containing the word '$word'. Return ONLY a JSON object: {\"sentence\": \"...\", \"translation\": \"...\"}. No markdown.";
      final response = await model.generateContent([Content.text(prompt)]);
      if (response.text != null) {
        String cleanedText = response.text!.trim();
        if (cleanedText.contains('{')) {
          int start = cleanedText.indexOf('{');
          int end = cleanedText.lastIndexOf('}') + 1;
          cleanedText = cleanedText.substring(start, end);
        }
        return Map<String, String>.from(jsonDecode(cleanedText));
      }
    } catch (e) { print("Gemini Error: $e"); }
    return null;
  }
}

class StorageService {
  static List<Word> _allCache = [];

  static Future<void> ensureInitialized(DBHelper dbHelper) async {
    final prefs = await SharedPreferences.getInstance();
    bool isInit = prefs.getBool('tv_voca_v18_init') ?? false;
    if (isInit) return;

    List<String> rawData = [
      "1|fix|수리하다. 고치다/2|shade|그늘/3|bury|묻다/4|cave|동굴/5|useful|유용한/6|dot|점/7|copy|복사/8|through|통과하여/9|oven|오븐/10|lend|빌려주다/11|moment|순간, 시점/12|wing|날개/13|neighbor|이웃/14|piece|조각, 한 개/15|still|여전히/16|twin|쌍둥이/17|pure|순수한, 맑은/18|stage|단계, 무대/19|at first|처음에는/20|put on|~을 입다/21|war|전쟁/22|cash|현금/23|advice|충고, 조언/24|lead|안내하다, 지도하다/25|perfect|완벽한/26|search|찾다/27|contest|대회/28|display|전시하다/29|tip|끝, 봉사료, 조언/30|borrow|빌리다/31|sharp|뾰족한/32|machine|기계/33|trouble|어려움/34|roll|구르다/35|exit|출구/36|proud|자랑스러운, 거만한/37|flood|홍수/38|stamp|우표, 도장/39|at last|마침내/40|grow up|자라다, 성장하다/41|mix|섞다/42|healthy|건강한/43|active|활동적인/44|dig|파다/45|simple|간단한, 단순한/46|view|경치, 의견/47|insect|곤충/48|sleepy|졸린/49|root|뿌리, 근원/50|total|총, 전체의/51|final|마지막의, 결승/52|scene|장면, 경치/53|prize|상, 상품/54|nickname|별명/55|pan|팬, 프라이팬/56|cartoon|만화/57|leader|지도자, 리더/58|coach|코치, 감독/59|find out|~을 알아내다/60|be in trouble|어려움에 처하다/61|lift|올리다/62|pack|포장하다/63|score|득점, 점수/64|court|법정, 경기장/65|desert|사막/66|award|상/67|elder|노인/68|among|~사이에/69|male|남성, 수컷/70|finally|마침내, 결국/71|sometime|언젠가/72|rule|규칙/73|harmony|조화, 화합/74|bark|짖다/75|crash|충돌, 추락/76|nature|자연/77|valley|계곡, 골짜기/78|wonder|궁금하다, 놀라운/79|think up|~을 생각해내다/80|be famous for|~로 유명하다/81|hang|걸다. 매달리다/82|able|~할 수 있는, 유능한/83|pain|통증, 고통/84|uniform|제복, 균일한/85|beauty|아름다움, 미인/86|taste|맛, 맛보다/87|shout|소리치다/88|without|~없이, 하지 않고/89|care|주의, 보살핌/90|sunlight|햇빛/91|female|여성, 암컷/92|lower|아래의, 낮추다/93|miss|놓치다. 그리워하다/94|exact|정확한/95|popular|인기 있는, 대중적인/96|regular|정기적인, 보통의/97|noisy|시끄러운/98|dive|뛰어들다/99|before long|머지않아/100|calm down|진정하다/101|pill|알약, 정제/102|alarm|경보/103|bored|지루한/104|freeze|얼다/105|nobody|아무도 ~않다/106|language|언어/107|teenager|십대/108|usual|평소의, 보통의/109|chance|가능성, 기회/110|hero|영웅/111|curl|곱슬곱슬하다/112|planet|행성/113|regularly|정기적으로/114|invent|발명하다/115|smart|영리한/116|dead|죽은/117|soil|흙/118|meal|식사, 끼니/119|take care|조심하다/120|because of|~때문에/121|coin|동전/122|prepare|준비하다/123|quite|꽤, 상당히/124|collect|모으다/125|main|주된/126|shower|샤워, 소나기/127|alike|비슷한/128|blank|공백의, 빈칸/129|freezing|몹시 추운/130|important|중요한/131|spicy|매콤한/132|teen|십대/133|weigh|무게가 ~이다/134|deaf|귀가 먹은/135|law|법, 법률/136|rub|비비다/137|pour|따르다. 붓다/138|yet|아직, 벌써/139|take out|~을 꺼내다/140|get out of|나가다/141|skill|기술/142|neat|정돈된, 단정한/143|ache|아픔/144|patient|환자/145|elderly|나이가 지긋한/146|mistake|실수/147|channel|채널/148|during|~동안/149|flour|밀가루/150|lawyer|변호사/151|tire|지치다/152|bar|막대기/153|soldier|군인/154|recipe|레시피/155|course|강의/156|wallet|지갑/157|guide|안내자/158|silent|조용한/159|fill in|기입하다. 써넣다/160|be different|~와 다르다/161|rail|레일, 철도, 기차/162|adult|성인/163|tasty|맛있는/164|couple|한 쌍, 부부/165|especially|특히/166|soap|비누/167|lonely|외로운/168|mind|마음, 정신/169|invention|발명/170|blind|눈먼/171|curly|곱슬곱슬한/172|stick|막대기/173|purse|(여성용)지갑, 핸드백/174|share|공유하다, 나누다/175|design|디자인/176|form|종류, 유형/177|wild|야생의/178|gallery|미술관/179|pick up|~을 집어들다/180|help out|도와주다/181|chat|수다, 담소/182|designer|디자이너/183|result|결과/184|type|종류, 유형/185|someday|언젠가/186|actual|실제의/187|culture|문화/188|lost|길을 잃은/189|item|물품, 품목/190|natural|자연의, 당연한/191|secret|비밀의/192|breath|숨, 호흡/193|excite|흥분시키다/194|online|온라인의/195|garbage|쓰레기/196|suck|빨다/197|prison|교도소, 감옥/198|flow|흐르다, 흐름/199|make noise|떠들다/200|hand in hand|서로 손을 잡고/201|solar|태양의/202|captain|선장, 기장/203|dialogue|대화, 회화/204|fail|실패하다/205|actually|실제로/206|special|특별한/207|tear|눈물, 찢다/208|however|그러나/209|burn|타다. 태우다/210|upstairs|위층에/211|living|살아 있는/212|report|보고, 보고하다/213|produce|생산하다. 낳다/214|cheer|환호, 환호하다/215|excited|신이 난, 흥분한/216|gather|모으다, 수집하다/217|save|구하다, 저축하다/218|cause|원인/219|exercise|운동/220|member|회원/221|press|누르다/222|serious|심각한/223|talent|재능/224|greet|맞이하다/225|beat|두드리다. 이기다/226|stress|스트레스, 강조/227|later|나중에, 후에/228|create|창조하다/229|flat|평평한/230|return|돌아가다/231|activity|활동/232|afraid|두려워하는/233|dessert|디저트, 후식/234|toothache|치통/235|in fact|사실은/236|no longer|더 이상 ~않다/237|effect|영향, 결과/238|focus|집중하다/239|dictionary|사전/240|allow|허락하다/241|print|인쇄하다/242|safely|안전하게/243|giant|거인, 거대한/244|usually|보통, 대개/245|creative|창의적인/246|review|검토하다/247|kiss|키스하다. 입맞춤/248|strange|이상한/249|comic|웃기는/250|mark|얼룩, 자국/251|shop|가게, 상점/252|talented|재능 있는, 유능한/253|bare|벌거벗은/254|housework|집안일/255|at least|적어도/256|pass through|지나가다. 겪다/257|rise|오르다/258|accept|받아들이다/259|topic|주제/260|flight|여행, 비행/261|hunter|사냥꾼/262|medicine|약, 의술/263|text|글, 본문/264|boil|끓다/265|pleasure|즐거움/266|dirt|먼지, 흙/267|everywhere|어디든지/268|sheet|시트, 얇은 천/269|village|마을/270|powerful|영향력 있는/271|scare|겁주다/272|step|걸음, 단계/273|cooking|요리/274|anger|화, 분노/275|look up|찾아보다/276|cut into pieces|~을 여러 조각으로 자르다/277|melt|녹다/278|straw|밀짚, 빨대/279|take care of|~을 돌보다/280|not anymore|더 이상 ~않다/281|own|소유하다/282|praise|칭찬하다/283|continue|계속되다/284|wooden|목재의/285|coast|해안/286|hike|하이킹, 도보 여행/287|scared|겁먹은/288|beyond|~저편에, ~을 지나서/289|meeting|회의/290|danger|위험/291|traffic|교통/292|even|~조차, 훨씬, 고른/293|foreign|외국의/294|lie|눕다/295|skip|빼다. 거르다/296|refuse|거절하다, 거부하다/297|plate|접시/298|alive|살아 있는/299|stay up|깨어 있다/300|get along with|~와 잘 지내다/301|sign|표지판, 서명하다/302|branch|나뭇가지, 지점, 지사/303|reach|도착하다 닿다/304|common|흔한, 공통의/305|path|길, 오솔길/306|core|핵심, 핵심적인/307|foreigner|외국인/308|toward|~쪽으로, ~을 향하여/309|vote|투표하다. 투표/310|headache|두통/311|interest|흥미, 관심/312|match|경기, 어울리다/313|owner|주인, 소유자/314|scary|무서운, 두려운/315|aid|도움/316|tradition|전통, 관습/317|per|~당, ~마다/318|wax|밀랍, 왁스/319|at that time|그때, 그 당시/320|sooner or later|조만간, 곧/321|judge|판사, 심판/322|agree|동의하다/323|basic|기초적인/324|drawer|서랍/325|greenhouse|온실/326|iron|철, 쇠/327|tower|탑/328|either|어느 한 쪽/329|mad|화가 난, 미친/330|straight|똑바로, 곧장/331|record|기록/332|solve|풀다, 해결하다/333|company|회사, 동료/334|nation|국가, 나라/335|pleased|기쁜, 만족스러운/336|control|통제, 지배/337|helpful|유익한/338|self|자신, 자아/339|run out|(시간, 돈) 다 떨어지다/340|after all|결국, 어쨌든/341|fry|튀기다. 볶다/342|habit|버릇, 습관/343|tax|세금/344|surprised|놀란, 놀라는/345|abroad|해외에/346|slide|미끄러지다/347|disagree|동의하지 않다/348|while|~하는 동안, 잠깐/349|row|열, 줄/350|festival|축제/351|aloud|소리 내어/352|shape|형태, 모양, 상태/353|tough|어려운, 굳센/354|cafeteria|구내식당/355|lock|잠그다/356|bottom|바닥/357|product|생산품, 제품/358|medal|메달, 훈장/359|get to|~에 도착하다/360|come true|이루어지다/361|sale|판매/362|metal|금속/363|complete|완벽한, 완료하다/364|general|전반적인, 일반의/365|parade|퍼레이드, 행진/366|royal|왕실의/367|ever|언젠가, 결코, 전혀/368|though|비록 ~이지만/369|direct|직접적인, 지휘하다/370|amazing|놀라운/371|clay|점토, 찰흙/372|bow|인사하다. 절하다/373|interview|면접, 인터뷰/374|outdoor|야외의/375|normal|보통의, 정상적인/376|factory|공장/377|peer|또래, 동료/378|sketch|스케치, 밑그림/379|after a while|잠시 후에/380|slow down|(속도)늦추다/381|base|밑, 바닥/382|grade|등급/383|signal|신호/384|meaning|의미, 뜻/385|cover|덮다. 다루다, 포함하다/386|awake|깨어 있는/387|quickly|빨리, 빠르게/388|trash|쓰레기/389|protect|보호하다. 지키다/390|evil|사악한, 악/391|character|성격, 특징, 등장인물/392|friendly|친절한/393|worried|걱정스러운/394|director|임원, 관리자, 감독/395|sentence|문장, 선고, 판결/396|loose|헐거운, 느슨한/397|indoor|실내의/398|puzzle|퍼즐, 수수께끼/399|take away|~을 치우다/400|have in common|공통적으로 ~을 가지다/401|bill|고지서, 지폐/402|cough|기침하다. 기침/403|image|이미지, 인상/404|national|국가의, 국립의/405|seed|씨앗/406|truth|진실, 사실/407|mixture|혼합/408|reuse|재사용하다/409|discover|발견하다. 깨닫다/410|junk|쓰레기/411|courage|용기/412|shine|빛나다/413|eastern|동쪽의/414|peace|평화, 평온함/415|fortune|부, 재산, 운/416|accident|사고, 우연/417|humor|유머/418|wrap|싸다. 포장하다/419|show up|나타나다. 모습을 드러내다/420|be covered with|~로 덮여 있다/421|breathe|호흡하다/422|gain|얻다, 늘다. 쌓다/423|fit|꼭 맞다. 적합하다/424|chief|최고의, 주요한/425|humorous|재미있는/426|unique|특별한/427|completely|완벽하게/428|pose|포즈를 취하다/429|adventure|모험/430|tight|꽉 끼는/431|stupid|우둔한/432|double|이중의/433|race|경기/434|express|표현하다/435|illegal|불법의/436|symbol|상징, 기호/437|mention|말하다. 언급하다/438|sum|금액, 합계/439|look through|~을 훑어보다/440|throw away|~을 버리다/441|bite|물다/442|society|사회, 단체/443|title|제목, 표제/444|anybody|누구나, 누군가/445|fever|열/446|scenery|풍경, 경치/447|order|명령하다, 주문하다/448|neither|어느 쪽도 ~아니다/449|diamond|다이아몬드/450|source|원천, 근원, 출처/451|contact|연락, 접촉/452|equal|동일한, 평등한/453|none|아무도 않다/454|period|기간/455|journey|여행/456|rough|거친/457|million|백만/458|ceiling|천장/459|give up|포기하다. 그만두다/460|hang out with|~와 어울리다/461|hug|껴안다/462|vision|시력, 전망/463|century|1세기/464|anywhere|어디든지, 어딘가에/465|nearly|거의/466|beard|턱수염/467|surround|둘러싸다/468|upper|더 위의/469|dynasty|왕조, 시대/470|whole|전체의, 모든/471|follow|따라가다 따르다/472|effort|노력/473|imagine|상상하다/474|shot|발사, 슛/475|pimple|여드름/476|raindrop|빗방울/477|ghost|유령/478|sweat|땀/479|care for|~을 돌보다/480|make up|이루다, 구성하다/481|huge|거대한, 막대한/482|tool|연장, 도구/483|attack|공격/484|battle|전투, 교전/485|universe|우주/486|global|세계적인/487|sudden|갑작스러운/488|rude|무례한/489|challenge|도전, 난제/490|frankly|솔직히/491|death|죽음/492|else|그 밖의, 다른/493|fantastic|환상적인, 멋진/494|swing|흔들리다, 휘두르다/495|master|대가, 주인/496|social|사회의, 사교의/497|code|암호, 부호/498|pedal|페달/499|watch out(for)|주의하다, 조심하다/500|not at all|전혀 아니다/501|action|행동, 조치/502|backward|뒤로/503|sore|아픈/504|daytime|낮/505|chore|일/506|impress|감동을 주다/507|fair|타당한/508|process|거정, 절차/509|comfort|편안함/510|suddenly|갑자기/511|host|주인, 진행자/512|graphic|그래픽의, 도표의/513|merry|명랑한, 즐거운/514|silence|고요, 침묵/515|trade|무역하다 교환하다/516|enemy|적/517|volume|음량/518|journal|잡지, 학술지/519|on time|제시간에/520|make fun of|~을 놀리다/521|pace|속도, 보폭/522|compare|비교하다. 비유하다/523|cloth|옷감, 천/524|novel|소설/525|rate|비율, 속도, 요금/526|gorgeous|멋진, 우아한/527|relax|쉬다/528|against|~에 반대하여/529|duty|의무, 직무, 임무/530|unfair|불공평한/531|traditional|전통의/532|prove|증명하다/533|seem|~처럼 보이다/534|equally|똑같이/535|modern|현대의/536|footprint|발자국/537|loudly|큰 소리로/538|seafood|해산물/539|stop by|잠시 들르다/540|be over|끝나다/541|mild|가벼운, 약한, 따뜻한/542|absent|결석한, 부재의/543|connect|연결하다. 관련시키다/544|fur|털, 모피/545|interested|흥미 있는/546|rival|경쟁자/547|decide|결정하다/548|throat|목구멍, 목/549|examination|시험, 조사, 금진/550|bump|부딪히다/551|golden|금색의/552|swimsuit|수영복/553|cancel|취소하다/554|passion|열정, 열망/555|stomach|위, 배/556|wheel|바퀴 핸들/557|sour|(맛)신, 상한/558|pole|막대기, 기둥/559|hand out|~을 나눠주다/560|try one's best|최선을 다하다/561|brick|벽돌/562|edge|가장자리/563|chase|뒤쫓다. 추적하다/564|fashionable|유행의/565|human|인간, 사람/566|mask|마스크, 가면/567|single|단독의, 독신의/568|therefore|그 결과/569|closely|면밀히, 밀접하게/570|divide|나뉘다. 분배하다/571|impression|인상, 감상/572|animation|만화/573|target|목표, 표적/574|repair|고치다. 수리하다/575|skin|피부/576|western|서쪽의/577|speed|속력, 속도/578|port|항구/579|ask for|~에게 ...을 요청하다/580|for the first time|처음으로/581|forward|앞으로/582|track|길, 자취, 추적하다/583|choice|선택권, 선택/584|shoot|쏘다/585|peel|껍질을 벗기다/586|decision|결정, 결심/587|quietly|조용히, 살짝/588|beside|옆에/589|clearly|명백하게, 분명히/590|repeat|다시 말하다, 반복하다/591|switch|스위치, 전환, 변경/592|landmark|주요 지형지물/593|goods|상품, 제품/594|announce|발표하다, 알리다/595|poem|시/596|electric|전기의/597|storm|폭풍/598|wire|철사/599|day by day|나날이, 서서히/600|turn into|~을 ...으로 바꾸다/601|advise|충고하다. 조언하다/602|introduce|소개하다/603|opinion|의견, 견해/604|smooth|매끈한, 부드러운/605|defend|방어하다/606|possible|가능한/607|wave|파도, 흔들다/608|nor|~도 또한 아니다/609|chemical|화학의/610|fake|가짜의/611|rapidly|빨리, 급속히/612|trust|신뢰/613|garage|차고/614|plain|분명한, 명백한/615|bother|괴롭히다/616|favorite|가장 좋아하는/617|victory|승리/618|salty|짠, 짭짤한/619|check out|~을 확인하다. 나가다/620|more and more|점점 더(많이)/621|birth|탄생, 출생/622|accent|말투, 악센트/623|educate|교육하다/624|forever|영원히/625|handle|처리하다 만지다/626|impossible|불가능한/627|lastly|끝으로/628|site|현장/629|condition|상태, 조건/630|doubt|의심하다/631|subject|주제, 화제/632|youth|젊은 시절/633|monster|괴물/634|stomachache|복통/635|public|대중의, 공공의/636|private|사적인, 개인의/637|task|일, 과업/638|circus|서커스, 곡예/639|run away|도망치다/640|at the same time|동시에, 한번에/641|apart|떨어져/642|poetry|시, 시가/643|balance|균형/644|chart|도표, 차트/645|damp|축축한, 습기찬/646|publish|발행하다 출판하다/647|weekday|평일/648|celebrate|축하하다/649|triangle|삼각형/650|electricity|전기/651|fear|공포/652|recent|최근의/653|injury|부상/654|select|선택하다, 고르다/655|haircut|이발/656|net|그물, 망, 네트/657|screen|화면, 스크린/658|shore|해안/659|fill out|~을 작성하다/660|more than|~보다 많이/661|offer|제의하다, 제공하다/662|address|주소, 연설/663|bitter|(맛)쓴, 쓰라린/664|cancer|암/665|fold|접다/666|downtown|시내에로/667|crime|범죄/668|surface|표면/669|entrance|문, 입구, 입장/670|slice|조각/671|pattern|패턴, 양식/672|respect|존경하다, 존중하다/673|soul|영혼, 정신/674|instead|그 대신에/675|muscle|근육/676|unit|구성단위, 단위/677|powder|가루, 분말/678|theme|주제, 테마/679|as well|또한, 역시/680|hand in|~을 제출하다/681|cycle|순환/682|degree|온도, 각도, 정도/683|bend|굽히다, 숙이다/684|reason|이유, 근거/685|safety|안전/686|asleep|잠든/687|confident|자신감 있는/688|wavy|물결 모양의/689|tube|관, 통/690|attend|출석하다/691|destroy|파괴하다/692|visitor|손님/693|emotion|감정/694|spin|돌다/695|southern|남쪽의/696|fortunately|운좋게 다행히/697|guest|손님, 하객/698|pump|퍼 올리다/699|take place|일어나다/700|instead of|~대신에/701|origin|기원, 태생/702|major|주요한, 중대한/703|appear|나타나다/704|fabric|천, 직물/705|customer|손님/706|importance|중요성/707|candle|양초/708|although|비록 ~일지라도/709|expect|기대하다/710|sink|가라앉다. 싱크대/711|trick|속임수, 장난, 마술/712|detail|세부 사항/713|remind|상기시키다/714|happen|일어나다 발생하다/715|beg|간청하다 부탁하다/716|plenty|많음, 충분, 다량/717|schoolwork|학업/718|steal|훔치다/719|end up with|결국 ~하게 되다/720|would like to v|~v 하고 싶다/721|feed|먹이를 주다/722|pile|쌓다. 더미/723|reply|대답하다. 대답/724|similar|비슷한/725|awful|끔찍한/726|escape|탈출하다/727|overcome|극복하다/728|anyway|어쨌든/729|blend|섞이다/730|disappear|사라지다/731|found|설립하다/732|international|국제적인/733|curious|궁금한/734|shock|충격을 주다/735|worth|가치가 있는, 유용성/736|cell|세포/737|scream|소리치다/738|provide|제공하다/739|get together|만나다/740|talk to oneself|혼잣말하다/741|brain|뇌, 지능/742|disease|질병/743|gesture|몸짓, 제스처/744|locker|사물함/745|remember|기억하다/746|curiosity|호기심/747|athlete|(운동) 선수/748|such|그러한, 매우~한/749|article|글, 기사, 논문/750|capital|수도, 자금, 대문자/751|explain|설명하다. 해명하다/752|forget|잊다/753|manner|방법, 태도, 예의/754|navy|해군/755|skillful|능숙한/756|tune|곡, 선율, 조율하다/757|sticky|끈적끈적한/758|perhaps|아마, 어쩌면/759|in need|어려움에 처한/760|come across|우연히 마주치다/761|sense|감각, 느낌/762|army|육군/763|booth|작은 공간, 부스/764|conduct|수행하다. 행위/765|fault|잘못, 과실/766|ladder|사다리/767|heal|낫다/768|difference|차이/769|success|성공/770|violent|폭력적인/771|guard|보호하다. 경비/772|manage|관리하다/773|remain|여전히 ~이다/774|exchange|교환/775|castle|성/776|northern|북쪽의/777|pillow|베개/778|tomb|무덤/779|set up|~을 세우다, 설치하다/780|all the time|항상, 늘/781|sight|시력, 시야/782|amount|양, 액수/783|bold|용감한, 굵은/784|community|지역사회/785|diet|식사, 다이어트/786|explore|탐험하다, 조사하다/787|grain|곡물/788|represent|대표하다/789|disappointed|실망한/790|wealth|재산/791|solution|해법, 정답/792|loss|분실, 상실/793|notice|알아차리다/794|poison|독/795|series|연속, 일련/796|tribe|종족/797|failure|실패/798|cage|우리, 새장/799|ahead of|~앞에/800|in short|요약하면/801|familiar|익숙한/802|argue|언쟁하다/803|honor|명예, 영광/804|campaign|운동, 캠페인/805|delight|기쁘게하다. 기쁨/806|cable|전선, 케이블/807|zone|구역, 지대/808|memory|기억, 추억/809|expression|표현, 표정/810|pipe|관, 파이프/811|volunteer|지원자, 자원봉사자/812|spill|쏟아지다. 쏟다/813|physical|신체의/814|lean|기울이다. 숙이다/815|research|연구하다. 조사하다/816|include|포함하다/817|successful|성공적인/818|silly|어리석은/819|be filled with|~로 가득 차다/820|on one's way(to)|(~로 가는)길에/821|ease|쉬움, 용이함/822|force|힘/823|average|평균, 보통 수준의/824|relationship|관계/825|information|정보, 자료/826|pollute|더럽히다/827|smoke|흡연하다. 연기/828|document|서류, 문서/829|ancient|고대의/830|succeed|성공하다/831|kindness|친절/832|growth|성장, 증대, 증가/833|university|대학교/834|crazy|정신 나간/835|newborn|갓 태어난/836|virus|바이러스/837|chemistry|화학/838|steel|강철/839|cut down|베어 쓰러뜨리다. 줄이다/840|be familiar with|~에 익숙하다/841|value|가치, 유용성/842|cast|내던지다 보내다/843|fame|명성, 명예/844|object|물건, 목표, 반대하다/845|recycle|재활용하다/846|schedule|일정, 시간표/847|stare|응시하다/848|probably|아마도/849|supply|공급하다/850|debt|빚, 부채/851|experience|경험하다. 겪다/852|instant|즉각적인, 인스턴트의/853|bacteria|세균/854|appropriate|적절한/855|comment|논평하다/856|apology|사과/857|magnet|자석/858|tap|수도꼭지, 톡톡 치다/859|hang on|붙잡다/860|get used to|~에 익숙해지다/861|blame|비난하다/862|realize|인식하다/863|tend|~하는 경향이 있다/864|college|(단과)대학/865|comfortable|편안한/866|scold|꾸짖다/867|freedom|자유/868|hardly|거의 ~않다/869|lay|놓다. 낳다/870|separate|분리된/871|moonlight|달빛/872|pity|동정하다/873|discuss|토론하다/874|education|교육/875|pardon|용서하다. 사면하다/876|wisdom|현명함, 지혜/877|afterward|후에, 나중에/878|slip|미끄러지다/879|one another|서로/880|take part in|~에 참여하다/881|figure|수치, 인물/882|gap|갈라진 틈, 공백, 격차/883|satisfy|만족시키다, 채우다/884|valuable|유용한, 값비싼/885|closet|벽장/886|diligent|부지런한/887|consume|소비하다/888|flash|번쩍이다/889|improve|개선하다/890|attract|끌어들이다 끌다/891|position|위치, 자세, 입장/892|tease|놀리다. 괴롭히다/893|exhibition|전시회, 전시/894|narrow|좁은/895|brief|짧은, 간결한/896|restroom|화장실/897|shut|닫다/898|stretch|늘어나다/899|pull out|빼다. 뽑다, 손을 떼다/900|keep in mind|~을 기억하다/901|fuel|연료/902|spread|펼치다, 벌리다/903|analyze|분석하다/904|bullet|총알/905|dislike|싫어하다/906|engineer|기사, 기술자/907|frame|틀, 액자, 프레임/908|astronaut|우주비행사/909|wisely|현명하게/910|several|몇몇의/911|height|키, 높이, 고도/912|nervous|긴장한, 불안한/913|spot|장소, 발견하다/914|pollution|오염/915|cotton|면, 면직물, 목화/916|instrument|기구, 도구, 악기/917|certainly|확실히, 틀림없이/918|typhoon|태풍/919|pull up|멈추다/920|run across|~을 우연히 마주치다/921|liberty|자유/922|feather|털, 깃털/923|compass|나침반, 컴퍼스/924|deliver|배달하다, 강연하다/925|earthquake|지진/926|strength|힘, 강점, 장점/927|treasure|보물/928|unlike|~와 다른/929|announcer|아나운서/930|state|상태, (미국 등의)주/931|bless|축복하다/932|heaven|천국/933|purpose|목적/934|inform|알리다/935|neighborhood|지역, 이웃/936|regret|후회하다/937|various|다양한/938|canal|운하/939|make it|성공하다/940|sign up for|~을 신청하다/941|spray|뿌리다. 분무기/942|delivery|배달/943|friendship|우정/944|horror|공포/945|climbing|등산/946|justice|정의, 재판/947|concern|걱정, 관심사/948|extra|추가의, 추가로/949|appearance|외모, 등장, 출현/950|original|원본의, 독창적인/951|infection|전염, 감염/952|counsel|상담하다/953|waste|낭비하다/954|spoil|망치다/955|polar|남(북)극의, 극지방의/956|relate|관련짓다/957|vet|수의사/958|tragedy|비극/959|such as|~와 같은/960|give away|폭로하다/961|anytime|언제든지/962|business|사업/963|credit|외상 거래, 칭찬/964|describe|말하다/965|forgive|용서하다/966|stroke|타격, 뇌졸중/967|humble|겸손한/968|upon|~위에/969|idiom|관용구/970|launch|시작하다. 발사하다/971|mount|증가하다, 오르다/972|photographer|사진가/973|string|끈/974|cardboard|판지, 마분지/975|supper|저녁 식사/976|terrible|끔찍한, 형편없는/977|evidence|증거/978|riddle|수수께끼/979|put up|~을 올리다/980|be related to|~와 관계가 있다/981|bet|돈을 걸다. 내기/982|script|대본/983|recommend|추천하다, 권장하다/984|career|직업, 경력/985|advantage|이점, 장점/986|float|뜨다, 떠다니다/987|champion|챔피언/988|local|지역의/989|difficulty|어려움/990|suffer|고통 받다. 겪다/991|environment|환경/992|totally|완전히/993|narrator|서술자, 내레이터/994|uneasy|불안한/995|route|길, 경로/996|portrait|초상화, 인물사진/997|motto|좌우명, 모토/998|slave|노예/999|give off|내뿜다/1000|work out|운동하다/1001|treat|대하다, 치료하다/1002|classic|고전적인/1003|account|계좌, 설명, 기술/1004|partner|동료, 상대/1005|collaborate|협력하다/1006|expert|전문가/1007|situation|상황/1008|within|이내에/1009|distance|거리/1010|favor|호의, 지지/1011|individual|개인의/1012|serve|제공하다/1013|bit|조금, 약간/1014|sneeze|재채기하다/1015|material|재료, 소재/1016|generally|일반적으로, 대개/1017|vivid|생생한/1018|rubber|고무/1019|use up|~을 다 쓰다/1020|make a decision|결정하다/1021|exist|존재하다/1022|relative|친척, 상대적인/1023|apologize|사과하다/1024|virtual|실질적인, 가상의/1025|maximum|최대/1026|complain|항의하다/1027|spirit|마음, 영혼/1028|since|이후, 한 이래로/1029|harm|해치다/1030|crowded|붐비는/1031|truly|정말로/1032|disadvantage|약점/1033|filter|여과하다. 거르다/1034|independence|독립/1035|positive|낙관적인/1036|suggest|제안하다/1037|arrest|체포하다. 구속하다/1038|unexpected|뜻밖의/1039|account for|~에 대해 설명하다/1040|be about to|막 ~하려고 하다/1041|chain|사슬, 연속, 체인점/1042|former|이전의, 과거의/1043|minimum|최소/1044|opposite|반대편에, 반대의/1045|disappoint|실망시키다/1046|slightly|약간, 조금/1047|artificial|인공의, 거짓의/1048|bunch|다발, 송이/1049|communicate|의사소통하다/1050|interpret|설명하다. 통역하다/1051|lid|뚜껑/1052|twisted|뒤틀린/1053|survey|설문 조사하다/1054|respond|대답하다/1055|environmental|환경의/1056|strip|벗다. 벗기다/1057|priest|성직자, 신부/1058|vary|다양하다. 바꾸다/1059|most of all|무엇보다도/1060|give a hand|도와주다/1061|cheat|부정행위하다, 속이다/1062|achieve|성취하다/1063|creature|생물/1064|extreme|극도의/1065|reduce|줄이다/1066|feature|특징, 특색/1067|knit|뜨개질하다/1068|whenever|~할 때마다/1069|graduate|졸업하다/1070|background|배경, 전후 사정/1071|stripe|줄무늬/1072|movement|동작, 운동, 활동/1073|option|선택/1074|personality|성격, 특성/1075|shame|수치심, 안타까운 일/1076|suppose|생각하다, 가정하다/1077|decorate|장식하다/1078|rhythm|리듬/1079|in case of|~의 경우에는/1080|on one's own|스스로, 혼자 힘으로/1081|layer|층, 겹/1082|survive|생존하다/1083|ashamed|부끄러워하는/1084|behave|행동하다/1085|competition|경쟁, 대회/1086|deny|부인하다/1087|necessary|필요한/1088|clever|영리한/1089|presentation|증정, 수여, 발표/1090|method|방법/1091|transfer|이동하다. 환승하다/1092|slight|약간의/1093|require|필요로 하다/1094|strike|치다. 파업/1095|well-known|유명한/1096|fantasy|환상/1097|envelope|봉투/1098|ordinary|보통의, 평범한/1099|hold out|저항하다. 버티다/1100|pass away|사망하다. 돌아가시다/1101|edit|수정하다. 편집하다/1102|receipt|영수증/1103|statue|조각상/1104|available|이용할 수 있는/1105|banner|현수막/1106|apply|지원, 신청, 적용/1107|digest|소화되다/1108|congratulation|축하/1109|depressed|우울한/1110|gradually|서서히/1111|hunger|배고픔, 갈망, 열망/1112|insert|넣다. 삽입하다/1113|mission|임무, 사명/1114|system|체계, 제도, 체제/1115|tender|다정한, 애정 어린/1116|unfortunately|유감스럽게도/1117|fountain|분수/1118|stove|난로, 조리기, 레인지/1119|put together|~을 조립하다 만들다/1120|on the other hand|반면에, 한편으로는/1121|forecast|예측, 예보/1122|awesome|굉장한/1123|consult|상담하다/1124|deal|다루다, 처리하다. 거래/1125|empire|제국/1126|satellite|위성, 인공위성/1127|upset|화난, 속상한/1128|communication|의사소통/1129|develop|발전하다/1130|escalate|악화되다. 증가하다/1131|invitation|초대/1132|migrate|이동하다, 이주하다/1133|raw|날것의/1134|poverty|가난, 빈곤/1135|station|역, 정류장/1136|grocery|식료품/1137|studio|방송실, 스튜디오/1138|unbelievable|믿을 수 없는/1139|be stuck in|~에 갇히다/1140|tell from|~와 ...을 구분하다/1141|leap|뛰다. 뛰어넘다/1142|support|지지하다, 부양하다/1143|proverb|속담/1144|argument|논쟁, 주장/1145|billion|10억/1146|organization|조직, 단체, 기구/1147|following|다음의/1148|except|~을 제외하고/1149|tag|꼬리표/1150|responsible|책임이 있는/1151|encourage|격려하다/1152|harvest|수확하다. 추수하다/1153|miserable|비참한/1154|stranger|낯선 사람/1155|concrete|구체적인, 콘크리트로 된/1156|servant|하인, 종, 고용인/1157|waterproof|방수의/1158|underground|지하의/1159|up to|~까지/1160|come to mind|생각이 떠오르다/1161|risk|위험/1162|behavior|행동/1163|amusement|즐거움, 재미/1164|consider|고려하다. ~로 여기다/1165|nest|둥지, 보금자리/1166|embarrass|당황스럽게 만들다/1167|clerk|직원, 점원/1168|observe|관찰하다. 준수하다/1169|sightseeing|관광/1170|transport|수송하다. 옮기다/1171|suit|정장, 슈트/1172|participate|참가하다/1173|faucet|수도꼭지/1174|mysterious|이해하기 힘든/1175|mud|진흙/1176|structure|구조, 구성/1177|hatch|부화하다/1178|optimist|낙관론자/1179|watch over|~을 보살피다/1180|to one's surprise|놀랍게도/1181|link|연결하다/1182|description|설명, 묘사/1183|sincere|진실된/1184|temperature|온도, 체온/1185|feast|연회, 잔치/1186|dew|이슬/1187|persuade|설득하다/1188|operator|조작자, 기사/1189|motivate|동기를 부여하다/1190|function|작동하다. 기능/1191|paralyze|마비시키다/1192|construction|건설, 공사/1193|revolution|혁명/1194|hurricane|허리케인/1195|experiment|실험하다. 실험/1196|performance|공연, 연기, 성과/1197|spaceship|우주선/1198|surprisingly|놀랍게도/1199|bring back|~을 기억나게 하다/1200|a variety of|다양한, 여러 가지의/"
    ];

    if (!kIsWeb) {
      final db = await dbHelper.database;
      Batch batch = db.batch();
      for (String block in rawData) {
        final pairs = block.split('/').where((s) => s.isNotEmpty);
        for (String pair in pairs) {
          final parts = pair.split('|');
          if (parts.length >= 3) {
            batch.insert('words', Word(word: parts[1].trim(), meaning: parts[2].trim()).toMap());
          }
        }
      }
      await batch.commit(noResult: true);
    } else {
      List<Map<String, dynamic>> maps = [];
      for (String block in rawData) {
        final pairs = block.split('/').where((s) => s.isNotEmpty);
        for (String pair in pairs) {
          final parts = pair.split('|');
          if (parts.length >= 3) {
            maps.add(Word(word: parts[1].trim(), meaning: parts[2].trim()).toMap());
          }
        }
      }
      _allCache = maps.map((m) => Word.fromMap(m)).toList();
      await prefs.setString('web_voca_data', jsonEncode(maps));
    }
    await prefs.setBool('tv_voca_final_init', true);
  }

  static Future<List<Word>> getAllWords(DBHelper dbHelper) async {
    if (kIsWeb) {
      if (_allCache.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        String? data = prefs.getString('web_voca_data');
        if (data != null) {
          Iterable l = jsonDecode(data);
          _allCache = List<Word>.from(l.map((m) => Word.fromMap(m as Map<String, dynamic>)));
        }
      }
      return _allCache;
    } else {
      final db = await dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query('words', orderBy: 'id ASC');
      return maps.map((m) => Word.fromMap(m)).toList();
    }
  }

  static Future<List<Word>> loadReviewWords(DBHelper dbHelper) async {
    if (kIsWeb) {
      await getAllWords(dbHelper);
      return _allCache.where((w) => w.isLearned == 0 || w.nextReview.isBefore(DateTime.now())).take(20).toList();
    } else {
      final db = await dbHelper.database;
      final now = DateTime.now().toIso8601String();
      final List<Map<String, dynamic>> maps = await db.query('words', 
        where: 'nextReview <= ? OR isLearned = 0', whereArgs: [now],
        orderBy: 'isLearned DESC, nextReview ASC', limit: 20
      );
      return maps.map((m) => Word.fromMap(m)).toList();
    }
  }

  static Future<void> updateWord(DBHelper dbHelper, Word word) async {
    if (kIsWeb) {
      int idx = _allCache.indexWhere((w) => w.word == word.word);
      if (idx != -1) _allCache[idx] = word;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_voca_data', jsonEncode(_allCache.map((w) => w.toMap()).toList()));
    } else {
      await dbHelper.updateWord(word);
    }
  }

  static Future<int> getLearnedCount(DBHelper dbHelper) async {
    if (kIsWeb) {
      await getAllWords(dbHelper);
      return _allCache.where((w) => w.isLearned == 1).length;
    }
    return await dbHelper.getLearnedCount();
  }
}

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;
  DBHelper._internal();
  factory DBHelper() => _instance;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }
  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'tv_voca_final_v5.db');
    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY AUTOINCREMENT, word TEXT, meaning TEXT, sentence TEXT, translation TEXT, interval INTEGER, easeFactor REAL, nextReview TEXT, isLearned INTEGER)');
    });
  }
  Future<int> getLearnedCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) FROM words WHERE isLearned = 1');
    return Sqflite.firstIntValue(res) ?? 0;
  }
  Future<void> updateWord(Word word) async {
    final db = await database;
    await db.update('words', word.toMap(), where: 'word = ?', whereArgs: [word.word]);
  }
}

// ==========================================
// 3. 상태 관리 (WordProvider)
// ==========================================
class WordProvider with ChangeNotifier {
  List<Word> _studyWords = [];
  List<Word> _allWords = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  bool _isAnswerRevealed = false;
  int _learnedCount = 0;

  final ApiService _apiService = ApiService();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  WordProvider() { _initVoice(); }
  Future<void> _initVoice() async { await _tts.setLanguage("en-US"); await _speech.initialize(); }

  List<Word> get studyWords => _studyWords;
  List<Word> get allWords => _allWords;
  bool get isLoading => _isLoading;
  bool get isAnswerRevealed => _isAnswerRevealed;
  int get learnedCount => _learnedCount;
  Word? get currentWord => _studyWords.isNotEmpty && _currentIndex < _studyWords.length ? _studyWords[_currentIndex] : null;

  Future<void> initDashboard() async {
    _isLoading = true;
    notifyListeners();
    await StorageService.ensureInitialized(DBHelper());
    _studyWords = await StorageService.loadReviewWords(DBHelper());
    _learnedCount = await StorageService.getLearnedCount(DBHelper());
    _allWords = await StorageService.getAllWords(DBHelper());
    _isLoading = false;
    _currentIndex = 0;
    _isAnswerRevealed = false;
    notifyListeners();
  }

  Future<void> speak(String text) async => await _tts.speak(text);
  
  Future<void> startListening(Function(String) onResult) async {
    if (await _speech.initialize()) { 
      _speech.listen(onResult: (val) {
        onResult(val.recognizedWords);
      }); 
      notifyListeners(); 
    }
  }
  void stopListening() { _speech.stop(); notifyListeners(); }
  bool get isListening => _speech.isListening;

  Future<void> prepareExample() async {
    if (currentWord != null && currentWord!.needsAiExample) {
      _isLoading = true;
      notifyListeners();
      final res = await _apiService.fetchExample(currentWord!.word);
      if (res != null) {
        currentWord!.sentence = res['sentence'];
        currentWord!.translation = res['translation'];
        await StorageService.updateWord(DBHelper(), currentWord!);
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  // 정답을 맞히면 단어가 채워진 예문 전체를 읽어줍니다.
  void revealAnswer() { 
    _isAnswerRevealed = true; 
    if(currentWord != null) {
      speak(currentWord!.sentence ?? currentWord!.word); 
    }
    notifyListeners(); 
  }

  Future<void> submitDifficulty(Difficulty difficulty) async {
    if (currentWord == null) return;
    currentWord!.processReview(difficulty);
    await StorageService.updateWord(DBHelper(), currentWord!);
    _isAnswerRevealed = false;
    _currentIndex++;
    _learnedCount = await StorageService.getLearnedCount(DBHelper());
    if (_currentIndex < _studyWords.length) await prepareExample();
    notifyListeners();
  }
}

// ==========================================
// 4. UI (App & Screens)
// ==========================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => WordProvider()..initDashboard())],
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TV VOCA',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo, fontFamily: 'Pretendard'),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WordProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("TV VOCA", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VocabularyScreen())),
            tooltip: "전체 단어장",
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text("전체 학습 리포트", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            LinearProgressIndicator(value: provider.learnedCount / 1200, minHeight: 12, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 10),
            Text("학습 완료: ${provider.learnedCount} / 1200 단어", style: const TextStyle(fontSize: 16)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: provider.isLoading ? null : () async {
                  if (provider.studyWords.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모든 학습을 완료했습니다!")));
                  } else {
                    await provider.prepareExample();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const QuizScreen()));
                  }
                },
                child: provider.isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text("학습 시작 (20개 단위)", style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});
  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WordProvider>();
    final filtered = provider.allWords.where((w) => 
      w.word.toLowerCase().contains(_query.toLowerCase()) || 
      w.meaning.contains(_query)
    ).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("전체 단어장")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "단어 또는 뜻 검색",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                  _searchController.clear();
                  setState(() => _query = "");
                }) : null,
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final w = filtered[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: w.isLearned == 1 ? Colors.green.shade100 : Colors.grey.shade100,
                    child: Text("${index + 1}", style: TextStyle(fontSize: 12, color: w.isLearned == 1 ? Colors.green : Colors.grey)),
                  ),
                  title: Text(w.word, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(w.meaning),
                  trailing: w.isLearned == 1 ? const Icon(Icons.check_circle, color: Colors.green) : null,
                  onTap: () => provider.speak(w.word),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final TextEditingController _controller = TextEditingController();

  // 정답 및 오답 판별 피드백 함수
  void _checkAnswer(String input, WordProvider provider, Word word) {
    if (input.isEmpty) return;
    
    // 사용자가 말하거나 입력한 텍스트에 정답 단어가 포함되어 있는지 확인
    if (input.trim().toLowerCase() == word.word.toLowerCase() || 
        input.toLowerCase().contains(word.word.toLowerCase())) {
      
      if (provider.isListening) provider.stopListening();
      provider.revealAnswer(); // 정답 처리 및 전체 예문 읽기
      _controller.clear();
      
      // 정답 팝업창
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("정답입니다! 🎉", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), backgroundColor: Colors.green, duration: Duration(seconds: 2))
      );
    } else if (!provider.isListening) {
      // 오답 팝업창 (마이크가 꺼진 상태에서 입력된 내용이 틀렸을 경우)
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("틀렸습니다. 다시 시도해보세요! 🥲", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.red, duration: Duration(seconds: 1))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WordProvider>();
    final word = provider.currentWord;
    if (word == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              const Text("20개 학습 완료!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: () { provider.initDashboard(); Navigator.pop(context); }, 
                icon: const Icon(Icons.refresh), label: const Text("다음 20개 더 공부하기")
              )
            ],
          )
        )
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text("학습 중 (${provider._currentIndex + 1} / ${provider.studyWords.length})")),
      body: provider.isLoading 
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Gemini가 일상 예문을 만들고 있어요...")]))
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                GestureDetector(
                  // 맞히기 전에는 빈칸 문장만 읽어주고, 맞힌 후에는 전체를 읽어줌
                  onTap: () => provider.speak(provider.isAnswerRevealed ? (word.sentence ?? word.word) : word.maskedSentence),
                  child: Card(
                    color: Colors.indigo.shade50,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(children: [
                        const Icon(Icons.volume_up, color: Colors.indigo, size: 32),
                        const SizedBox(height: 16),
                        // 빈칸으로 뚫린 예문 보여주기
                        Text(provider.isAnswerRevealed ? (word.sentence ?? word.word) : word.maskedSentence, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        if (provider.isAnswerRevealed && word.translation != null) ...[const SizedBox(height: 12), Text(word.translation!, style: const TextStyle(fontSize: 16, color: Colors.indigo))]
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(word.meaning, style: const TextStyle(fontSize: 20, color: Colors.black87, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (!provider.isAnswerRevealed) ...[
                  TextField(
                    controller: _controller,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      hintText: provider.isListening ? "듣고 있어요..." : "마이크를 누르고 말해보세요!",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: Icon(provider.isListening ? Icons.mic : Icons.mic_none, color: provider.isListening ? Colors.red : Colors.grey, size: 28),
                        onPressed: () { 
                          if (provider.isListening) {
                            provider.stopListening();
                            // 마이크 껐을 때 최종 확인
                            _checkAnswer(_controller.text, provider, word);
                          } else { 
                            provider.startListening((t) { 
                              setState(() => _controller.text = t); 
                              // 마이크로 말하는 도중에 실시간으로 정답인지 검사
                              _checkAnswer(t, provider, word);
                            }); 
                          } 
                        },
                      ),
                    ),
                    onSubmitted: (value) => _checkAnswer(value, provider, word),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity, 
                    height: 56, 
                    child: FilledButton(
                      onPressed: () => _checkAnswer(_controller.text, provider, word), 
                      child: const Text("정답 확인", style: TextStyle(fontSize: 18))
                    )
                  )
                ] else _diffRow(provider),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }
  
  Widget _diffRow(WordProvider p) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100, foregroundColor: Colors.red.shade900), onPressed: () => p.submitDifficulty(Difficulty.hard), child: const Text("어려움")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100, foregroundColor: Colors.orange.shade900), onPressed: () => p.submitDifficulty(Difficulty.good), child: const Text("보통")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100, foregroundColor: Colors.green.shade900), onPressed: () => p.submitDifficulty(Difficulty.easy), child: const Text("쉬움")),
    ]);
  }
}