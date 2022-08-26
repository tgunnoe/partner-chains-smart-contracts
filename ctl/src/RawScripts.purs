module RawScripts
  ( rawUpdateCommitteeHash
  , rawMPTRootTokenValidator
  , rawMPTRootTokenMintingPolicy
  , rawFUELMintingPolicy
  , rawCommitteeCandidateValidator
  ) where

rawCommitteeCandidateValidator ∷ String
rawCommitteeCandidateValidator =
  """{"type":"PlutusScriptV2","description":"","cborHex":"59094959094601000032323233223232323232323232323322323322323232323232232323232322323232323232223232533533300c3333573466e1cd55cea8052400046666664444442466666600200e00c00a0080060046eb8d5d0a8051bae35742a0126eb8d5d0a8041bae35742a00e603e6ae854018dd71aba135744a00c464c6404e66ae700a80a4094cccd5cd19b8735573a6ea80112000202923263202733573805405204a6666ae68cdc39aab9d5002480008cc8848cc00400c008c8c8c8c8c8c8c8c8c8c8c8c8c8cccd5cd19b8735573aa018900011999999999999111111111110919999999999980080680600580500480400380300280200180119a8110119aba1500c33502202335742a01666a0440486ae854028ccd54099d728129aba150093335502675ca04a6ae854020cd40880bcd5d0a803999aa8130183ad35742a00c6464646666ae68cdc39aab9d5002480008cc8848cc00400c008c8c8c8cccd5cd19b8735573aa004900011991091980080180119a81d3ad35742a00460766ae84d5d1280111931901e99ab9c04003f03b135573ca00226ea8004d5d0a8011919191999ab9a3370e6aae754009200023322123300100300233503a75a6ae854008c0ecd5d09aba2500223263203d33573808007e07626aae7940044dd50009aba135744a004464c6407266ae700f00ec0dc4d55cf280089baa00135742a00a66a044eb8d5d0a802199aa81301610009aba150033335502675c40026ae854008c0b8d5d09aba2500223263203533573807006e06626ae8940044d5d1280089aba25001135744a00226ae8940044d5d1280089aba25001135744a00226ae8940044d5d1280089aab9e5001137540026ae854008c078d5d09aba2500223263202733573805405204a2050264c6404c66ae712410350543500028135573ca00226ea80044d5d1280089aba25001135744a00226ae8940044d55cf280089baa001322225335323235002222222222222533533355301812001321233001225335002210031001002502125335333573466e3c0380040b80b44d408c00454088010840b840b0d4010888888004d400488008407c4cd5ce2481284d757374206265207369676e656420627920746865206f726967696e616c207375626d69747465720001e3333573466e1cd55cea8022400046666444424666600200a0080060046eb4d5d0a8021bae35742a0066464646666ae68cdc3a800a400046a02a602e6ae84d55cf280191999ab9a3370ea00490011280a91931901019ab9c02302201e01d135573aa00226ea8004d5d0a80118099aba135744a004464c6403666ae700780740644d5d1280089aba25001135573ca00226ea8004c8004d5406088448894cd40044d400c88004884ccd401488008c010008ccd54c01c4800401401000448c88c008dd6000990009aa80c111999aab9f0012500a233500930043574200460066ae880080608c8c8cccd5cd19b8735573aa004900011991091980080180118071aba150023005357426ae8940088c98c8058cd5ce00c80c00a09aab9e5001137540024646464646666ae68cdc39aab9d5004480008cccc888848cccc00401401000c008c8c8c8cccd5cd19b8735573aa0049000119910919800801801180b9aba1500233500f016357426ae8940088c98c806ccd5ce00f00e80c89aab9e5001137540026ae854010ccd54021d728039aba150033232323333573466e1d4005200423212223002004357426aae79400c8cccd5cd19b875002480088c84888c004010dd71aba135573ca00846666ae68cdc3a801a400042444006464c6403a66ae7008007c06c0680644d55cea80089baa00135742a00466a016eb8d5d09aba2500223263201733573803403202a26ae8940044d5d1280089aab9e500113754002266aa002eb9d6889119118011bab00132001355015223233335573e0044a010466a00e66442466002006004600c6aae754008c014d55cf280118021aba200301613574200222440042442446600200800624464646666ae68cdc3a800a400046a00e600a6ae84d55cf280191999ab9a3370ea00490011280391931900919ab9c01501401000f135573aa00226ea800448488c00800c44880048c8c8cccd5cd19b875001480188c848888c010014c01cd5d09aab9e500323333573466e1d400920042321222230020053009357426aae7940108cccd5cd19b875003480088c848888c004014c01cd5d09aab9e500523333573466e1d40112000232122223003005375c6ae84d55cf280311931900819ab9c01301200e00d00c00b135573aa00226ea80048c8c8cccd5cd19b8735573aa004900011991091980080180118029aba15002375a6ae84d5d1280111931900619ab9c00f00e00a135573ca00226ea80048c8cccd5cd19b8735573aa002900011bae357426aae7940088c98c8028cd5ce00680600409baa001232323232323333573466e1d4005200c21222222200323333573466e1d4009200a21222222200423333573466e1d400d2008233221222222233001009008375c6ae854014dd69aba135744a00a46666ae68cdc3a8022400c4664424444444660040120106eb8d5d0a8039bae357426ae89401c8cccd5cd19b875005480108cc8848888888cc018024020c030d5d0a8049bae357426ae8940248cccd5cd19b875006480088c848888888c01c020c034d5d09aab9e500b23333573466e1d401d2000232122222223005008300e357426aae7940308c98c804ccd5ce00b00a80880800780700680600589aab9d5004135573ca00626aae7940084d55cf280089baa0012323232323333573466e1d400520022333222122333001005004003375a6ae854010dd69aba15003375a6ae84d5d1280191999ab9a3370ea0049000119091180100198041aba135573ca00c464c6401866ae7003c0380280244d55cea80189aba25001135573ca00226ea80048c8c8cccd5cd19b875001480088c8488c00400cdd71aba135573ca00646666ae68cdc3a8012400046424460040066eb8d5d09aab9e500423263200933573801801600e00c26aae7540044dd500089119191999ab9a3370ea00290021091100091999ab9a3370ea00490011190911180180218031aba135573ca00846666ae68cdc3a801a400042444004464c6401466ae7003403002001c0184d55cea80089baa0012323333573466e1d40052002200623333573466e1d40092000200623263200633573801201000800626aae74dd5000a4c244004244002240029210350543100112323001001223300330020020011"}"""

rawFUELMintingPolicy ∷ String
rawFUELMintingPolicy =
  """{"type":"PlutusScriptV2","description":"","cborHex":"590a84590a81010000323322332232323232323232323232323232332232323232323232322323232323223232232325335330073333573466e1d40112002212200123333573466e1d401520002321223002003375c6ae84d55cf280391931901119ab9c02302202001f3333573466e1cd55cea80124000466442466002006004646464646464646464646464646666ae68cdc39aab9d500c480008cccccccccccc88888888888848cccccccccccc00403403002c02802402001c01801401000c008cd407807cd5d0a80619a80f00f9aba1500b33501e02035742a014666aa044eb94084d5d0a804999aa8113ae502135742a01066a03c0526ae85401cccd540880a9d69aba150063232323333573466e1cd55cea801240004664424660020060046464646666ae68cdc39aab9d5002480008cc8848cc00400c008cd40d1d69aba150023035357426ae8940088c98c80dccd5ce01c01b81a89aab9e5001137540026ae854008c8c8c8cccd5cd19b8735573aa004900011991091980080180119a81a3ad35742a004606a6ae84d5d1280111931901b99ab9c038037035135573ca00226ea8004d5d09aba2500223263203333573806806606226aae7940044dd50009aba1500533501e75c6ae854010ccd540880988004d5d0a801999aa8113ae200135742a00460506ae84d5d1280111931901799ab9c03002f02d135744a00226ae8940044d5d1280089aba25001135744a00226ae8940044d5d1280089aba25001135744a00226ae8940044d55cf280089baa00135742a00460306ae84d5d1280111931901099ab9c02202101f10201326320203357389210350543500020135573ca00226ea80044d55cea80089baa0013222350032222350052233335001202723500322222322222222533501621300925335333573466e2000520000370361037133573892011c43616e2774206275726e206120706f73697469766520616d6f756e740003615335300825335333573466e240052000035036103613357389211c43616e2774206d696e742061206e6567617469766520616d6f756e74000351533553350122133355301f12001323212330012233350052200200200100235001220011233001225335002103910010362325335333573466e3cd400488008d400c880080e00dc4ccd5cd19b87350012200135003220010380371037350012200200e103510351335738921264f6e6573686f74204d696e74696e67706f6c696379207574786f206e6f742070726573656e74000341034253353302b5030002102d2213500222253350041533530060011533553353301b00300c1033133573892119546f6b656e2053796d626f6c20697320696e636f727265637400032153353301b0024881044655454c001033133573892117546f6b656e204e616d6520697320696e636f72726563740003210321032221034202720273333573466e1cd55cea8022400046666444424666600200a0080060046eb4d5d0a8021bae35742a0066464646666ae68cdc3a800a400046a028602c6ae84d55cf280191999ab9a3370ea00490011280a11931900f99ab9c02001f01d01c135573aa00226ea8004d5d0a80118091aba135744a004464c6403466ae7006c0680604d5d1280089aba25001135573ca00226ea800488ccd5cd19b8f00200101a0193200135501a22112225335001135003220012213335005220023004002333553007120010050040011232230023758002640026aa034446666aae7c004940708cd406cc010d5d080118019aba2002014232323333573466e1cd55cea8012400046644246600200600460186ae854008c014d5d09aba2500223263201433573802a02802426aae7940044dd50009191919191999ab9a3370e6aae75401120002333322221233330010050040030023232323333573466e1cd55cea80124000466442466002006004602a6ae854008cd4034050d5d09aba2500223263201933573803403202e26aae7940044dd50009aba150043335500875ca00e6ae85400cc8c8c8cccd5cd19b875001480108c84888c008010d5d09aab9e500323333573466e1d4009200223212223001004375c6ae84d55cf280211999ab9a3370ea00690001091100191931900d99ab9c01c01b019018017135573aa00226ea8004d5d0a80119a804bae357426ae8940088c98c8054cd5ce00b00a80989aba25001135744a00226aae7940044dd5000899aa800bae75a224464460046eac004c8004d5405c88c8cccd55cf8011280d119a80c9991091980080180118031aab9d5002300535573ca00460086ae8800c0484d5d080089119191999ab9a3370ea002900011a80398029aba135573ca00646666ae68cdc3a801240044a00e464c6402466ae7004c04804003c4d55cea80089baa0011212230020031122001232323333573466e1d400520062321222230040053007357426aae79400c8cccd5cd19b875002480108c848888c008014c024d5d09aab9e500423333573466e1d400d20022321222230010053007357426aae7940148cccd5cd19b875004480008c848888c00c014dd71aba135573ca00c464c6402066ae7004404003803403002c4d55cea80089baa001232323333573466e1cd55cea80124000466442466002006004600a6ae854008dd69aba135744a004464c6401866ae700340300284d55cf280089baa0012323333573466e1cd55cea800a400046eb8d5d09aab9e500223263200a33573801601401026ea80048c8c8c8c8c8cccd5cd19b8750014803084888888800c8cccd5cd19b875002480288488888880108cccd5cd19b875003480208cc8848888888cc004024020dd71aba15005375a6ae84d5d1280291999ab9a3370ea00890031199109111111198010048041bae35742a00e6eb8d5d09aba2500723333573466e1d40152004233221222222233006009008300c35742a0126eb8d5d09aba2500923333573466e1d40192002232122222223007008300d357426aae79402c8cccd5cd19b875007480008c848888888c014020c038d5d09aab9e500c23263201333573802802602202001e01c01a01801626aae7540104d55cf280189aab9e5002135573ca00226ea80048c8c8c8c8cccd5cd19b875001480088ccc888488ccc00401401000cdd69aba15004375a6ae85400cdd69aba135744a00646666ae68cdc3a80124000464244600400660106ae84d55cf280311931900619ab9c00d00c00a009135573aa00626ae8940044d55cf280089baa001232323333573466e1d400520022321223001003375c6ae84d55cf280191999ab9a3370ea004900011909118010019bae357426aae7940108c98c8024cd5ce00500480380309aab9d50011375400224464646666ae68cdc3a800a40084244400246666ae68cdc3a8012400446424446006008600c6ae84d55cf280211999ab9a3370ea00690001091100111931900519ab9c00b00a008007006135573aa00226ea80048c8cccd5cd19b8750014800880288cccd5cd19b8750024800080288c98c8018cd5ce00380300200189aab9d37540029309000a481035054310032001355006222533500110022213500222330073330080020060010033200135500522225335001100222135002225335333573466e1c005200000a0091333008007006003133300800733500b12333001008003002006003122002122001112200212212233001004003112323001001223300330020020011"}"""

rawMPTRootTokenMintingPolicy ∷ String
rawMPTRootTokenMintingPolicy =
  """{"type":"PlutusScriptV2","description":"","cborHex":"590aff590afc010000323322332232323232323322323232323232323232323232323232323232323232335550192232323232232325335330093333573466e1cd55cea803a400046666444424666600200a0080060046eb8d5d0a80399a807bae35742a00c6eb4d5d0a80299a807bae357426ae8940148c98c8078cd5ce00f80f00e1999ab9a3370e6aae7540092000233221233001003002323232323232323232323232323333573466e1cd55cea8062400046666666666664444444444442466666666666600201a01801601401201000e00c00a00800600466a03a03c6ae854030cd4074078d5d0a80599a80e80f9aba1500a3335502175ca0406ae854024ccd54085d728101aba1500833501d02635742a00e666aa04204eeb4d5d0a8031919191999ab9a3370e6aae75400920002332212330010030023232323333573466e1cd55cea8012400046644246600200600466a062eb4d5d0a80118191aba135744a004464c6406866ae700d40d00c84d55cf280089baa00135742a0046464646666ae68cdc39aab9d5002480008cc8848cc00400c008cd40c5d69aba150023032357426ae8940088c98c80d0cd5ce01a81a01909aab9e5001137540026ae84d5d1280111931901819ab9c03103002e135573ca00226ea8004d5d0a80299a80ebae35742a008666aa04204640026ae85400cccd54085d710009aba150023025357426ae8940088c98c80b0cd5ce01681601509aba25001135744a00226ae8940044d5d1280089aba25001135744a00226ae8940044d5d1280089aba25001135744a00226aae7940044dd50009aba150023015357426ae8940088c98c8078cd5ce00f80f00e080e89a805a490350543500135573ca00226ea80044d5d1280089aba25001135573ca00226ea8004cd554064888d40088888d401488cccd400480a48d400c8888888888894cd54cd4cc0c140d002040d4884d40088894cd401054cd54cd4ccd5cd19b87001480080ec0e840ec4cd5ce248110416d6f756e74206d75737420626520310003a1533553353301e003012103b1335738920119546f6b656e2053796d626f6c20697320696e636f72726563740003a153353301e002018103b1335738920117546f6b656e204e616d6520697320696e636f72726563740003a103a103a22103c132533533355301b12001323212330012233350052200200200100235001220011233001225335002100110390382001330330135335013135019490103505439002210011333355301812001223335734666e540080580040e40e004800404c40d8cd54c0b848004800404040d480a480a48c8c8c8c8cccd5cd19b8735573aa00890001199991110919998008028020018011bad35742a0086eb8d5d0a8019919191999ab9a3370ea002900011a810980b1aba135573ca00646666ae68cdc3a801240044a042464c6403e66ae7008007c0740704d55cea80089baa00135742a00460246ae84d5d1280111931900d19ab9c01b01a018135744a00226ae8940044d55cf280089baa0013200135502022112322225335333573466e2400d2000026025102615335002102522153353300600200321333355300a120010083370200c900100100089999aa980489000803802800801990009aa811911299a8008a80d910a99a9980300200109a80f0008a99a99802802000909a80f99a8128018008a80e891931900999ab9c00101322333573466e3c00800407c078c8004d5407488448894cd40044d400c88004884ccd401488008c010008ccd54c01c4800401401000448c88c008dd6000990009aa80e911999aab9f0012501d233501c30043574200460066ae880080488c8c8cccd5cd19b8735573aa004900011991091980080180118051aba150023005357426ae8940088c98c8048cd5ce00980900809aab9e5001137540024646464646666ae68cdc39aab9d5004480008cccc888848cccc00401401000c008c8c8c8cccd5cd19b8735573aa004900011991091980080180118099aba1500233500d012357426ae8940088c98c805ccd5ce00c00b80a89aab9e5001137540026ae854010ccd54021d728039aba150033232323333573466e1d4005200423212223002004357426aae79400c8cccd5cd19b875002480088c84888c004010dd71aba135573ca00846666ae68cdc3a801a400042444006464c6403266ae7006806405c0580544d55cea80089baa00135742a00466a012eb8d5d09aba2500223263201333573802802602226ae8940044d5d1280089aab9e500113754002266aa002eb9d6889119118011bab0013200135501a223233335573e0044a036466a03466442466002006004600c6aae754008c014d55cf280118021aba200301013574200224464646666ae68cdc3a800a400046a024600a6ae84d55cf280191999ab9a3370ea00490011280911931900819ab9c01101000e00d135573aa00226ea80048c8c8cccd5cd19b875001480188c848888c010014c01cd5d09aab9e500323333573466e1d400920042321222230020053009357426aae7940108cccd5cd19b875003480088c848888c004014c01cd5d09aab9e500523333573466e1d40112000232122223003005375c6ae84d55cf280311931900819ab9c01101000e00d00c00b135573aa00226ea80048c8c8cccd5cd19b8735573aa004900011991091980080180118029aba15002375a6ae84d5d1280111931900619ab9c00d00c00a135573ca00226ea80048c8cccd5cd19b8735573aa002900011bae357426aae7940088c98c8028cd5ce00580500409baa001232323232323333573466e1d4005200c21222222200323333573466e1d4009200a21222222200423333573466e1d400d2008233221222222233001009008375c6ae854014dd69aba135744a00a46666ae68cdc3a8022400c4664424444444660040120106eb8d5d0a8039bae357426ae89401c8cccd5cd19b875005480108cc8848888888cc018024020c030d5d0a8049bae357426ae8940248cccd5cd19b875006480088c848888888c01c020c034d5d09aab9e500b23333573466e1d401d2000232122222223005008300e357426aae7940308c98c804ccd5ce00a00980880800780700680600589aab9d5004135573ca00626aae7940084d55cf280089baa0012323232323333573466e1d400520022333222122333001005004003375a6ae854010dd69aba15003375a6ae84d5d1280191999ab9a3370ea0049000119091180100198041aba135573ca00c464c6401866ae700340300280244d55cea80189aba25001135573ca00226ea80048c8c8cccd5cd19b875001480088c8488c00400cdd71aba135573ca00646666ae68cdc3a8012400046424460040066eb8d5d09aab9e500423263200933573801401200e00c26aae7540044dd500089119191999ab9a3370ea00290021091100091999ab9a3370ea00490011190911180180218031aba135573ca00846666ae68cdc3a801a400042444004464c6401466ae7002c02802001c0184d55cea80089baa0012323333573466e1d40052002201123333573466e1d40092000201123263200633573800e00c00800626aae74dd5000a4c24002921035054310012122300200311220013200135500922112253350011500a22133500b300400233553006120010040011112223003300200132001355007222533500110022213500222330073330080020060010033200135500622225335001100222135002225335333573466e1c005200000d00c1333008007006003133300800733500a1233300100800300200600332001355005222533500215005221533500315007221335008333573466e4001000802c028cc01c00c0044488008488488cc00401000c488008488004448c8c00400488cc00cc008008005"}"""

rawMPTRootTokenValidator ∷ String
rawMPTRootTokenValidator =
  """{"type":"PlutusScriptV2","description":"","cborHex":"59084559084201000032323232323232323232323232323322323322323232323232335550013232222232325335333006300800530070043333573466e1cd55cea80124000466442466002006004646464646464646464646464646666ae68cdc39aab9d500c480008cccccccccccc88888888888848cccccccccccc00403403002c02802402001c01801401000c008cd4064068d5d0a80619a80c80d1aba1500b33501901b35742a014666aa03aeb94070d5d0a804999aa80ebae501c35742a01066a03204c6ae85401cccd5407409dd69aba150063232323333573466e1cd55cea801240004664424660020060046464646666ae68cdc39aab9d5002480008cc8848cc00400c008cd40c5d69aba150023032357426ae8940088c98c80d8cd5ce01b81b01a09aab9e5001137540026ae854008c8c8c8cccd5cd19b8735573aa004900011991091980080180119a818bad35742a00460646ae84d5d1280111931901b19ab9c037036034135573ca00226ea8004d5d09aba2500223263203233573806606406026aae7940044dd50009aba1500533501975c6ae854010ccd5407408c8004d5d0a801999aa80ebae200135742a004604a6ae84d5d1280111931901719ab9c02f02e02c135744a00226ae8940044d5d1280089aba25001135744a00226ae8940044d5d1280089aba25001135744a00226ae8940044d55cf280089baa00135742a004602a6ae84d5d1280111931901019ab9c02102001e101f13263201f335738921035054350001f135573ca00226ea800540594054cd55400488880608c8c8c8c8cccd5cd19b8735573aa00890001199991110919998008028020018011bad35742a0086eb8d5d0a8019919191999ab9a3370ea002900011a80a980b9aba135573ca00646666ae68cdc3a801240044a02a464c6404466ae7008c08808007c4d55cea80089baa00135742a00460266ae84d5d1280111931900e99ab9c01e01d01b135744a00226ae8940044d55cf280089baa001111222300330020011232230023758002640026aa030446666aae7c004940288cd4024c010d5d080118019aba2002018232323333573466e1cd55cea80124000466442466002006004601c6ae854008c014d5d09aba2500223263201833573803203002c26aae7940044dd50009191919191999ab9a3370e6aae75401120002333322221233330010050040030023232323333573466e1cd55cea80124000466442466002006004602e6ae854008cd403c058d5d09aba2500223263201d33573803c03a03626aae7940044dd50009aba150043335500875ca00e6ae85400cc8c8c8cccd5cd19b875001480108c84888c008010d5d09aab9e500323333573466e1d4009200223212223001004375c6ae84d55cf280211999ab9a3370ea00690001091100191931900f99ab9c02001f01d01c01b135573aa00226ea8004d5d0a80119a805bae357426ae8940088c98c8064cd5ce00d00c80b89aba25001135744a00226aae7940044dd5000899aa800bae75a224464460046eac004c8004d5405488c8cccd55cf80112804119a8039991091980080180118031aab9d5002300535573ca00460086ae8800c0584d5d080088910010910911980080200189119191999ab9a3370ea002900011a80398029aba135573ca00646666ae68cdc3a801240044a00e464c6402866ae700540500480444d55cea80089baa0011212230020031122001232323333573466e1d400520062321222230040053007357426aae79400c8cccd5cd19b875002480108c848888c008014c024d5d09aab9e500423333573466e1d400d20022321222230010053007357426aae7940148cccd5cd19b875004480008c848888c00c014dd71aba135573ca00c464c6402466ae7004c04804003c0380344d55cea80089baa001232323333573466e1cd55cea80124000466442466002006004600a6ae854008dd69aba135744a004464c6401c66ae7003c0380304d55cf280089baa0012323333573466e1cd55cea800a400046eb8d5d09aab9e500223263200c33573801a01801426ea80048c8c8c8c8c8cccd5cd19b8750014803084888888800c8cccd5cd19b875002480288488888880108cccd5cd19b875003480208cc8848888888cc004024020dd71aba15005375a6ae84d5d1280291999ab9a3370ea00890031199109111111198010048041bae35742a00e6eb8d5d09aba2500723333573466e1d40152004233221222222233006009008300c35742a0126eb8d5d09aba2500923333573466e1d40192002232122222223007008300d357426aae79402c8cccd5cd19b875007480008c848888888c014020c038d5d09aab9e500c23263201533573802c02a02602402202001e01c01a26aae7540104d55cf280189aab9e5002135573ca00226ea80048c8c8c8c8cccd5cd19b875001480088ccc888488ccc00401401000cdd69aba15004375a6ae85400cdd69aba135744a00646666ae68cdc3a80124000464244600400660106ae84d55cf280311931900719ab9c00f00e00c00b135573aa00626ae8940044d55cf280089baa001232323333573466e1d400520022321223001003375c6ae84d55cf280191999ab9a3370ea004900011909118010019bae357426aae7940108c98c802ccd5ce00600580480409aab9d50011375400224464646666ae68cdc3a800a40084244400246666ae68cdc3a8012400446424446006008600c6ae84d55cf280211999ab9a3370ea00690001091100111931900619ab9c00d00c00a009008135573aa00226ea80048c8cccd5cd19b8750014800884880088cccd5cd19b8750024800080148c98c8020cd5ce00480400300289aab9d3754002244002246666ae68cdc39aab9d37540029000100211931900219ab9c0050040024984800524010350543100112323001001223300330020020011"}"""

rawUpdateCommitteeHash ∷ String
rawUpdateCommitteeHash =
  """{"type":"PlutusScriptV2","description":"","cborHex":"59090b59090801000032332233223232323232323232323232323232323232323232323355501322232325335330053333573466e1cd55ce9baa0044800080588c98c8058cd5ce00b80b00a1999ab9a3370e6aae7540092000233221233001003002323232323232323232323232323333573466e1cd55cea8062400046666666666664444444444442466666666666600201a01801601401201000e00c00a00800600466a02a02c6ae854030cd4054058d5d0a80599a80a80b9aba1500a3335501975ca0306ae854024ccd54065d7280c1aba1500833501501e35742a00e666aa03203eeb4d5d0a8031919191999ab9a3370e6aae75400920002332212330010030023232323333573466e1cd55cea8012400046644246600200600466a052eb4d5d0a80118151aba135744a004464c6405866ae700b40b00a84d55cf280089baa00135742a0046464646666ae68cdc39aab9d5002480008cc8848cc00400c008cd40a5d69aba15002302a357426ae8940088c98c80b0cd5ce01681601509aab9e5001137540026ae84d5d1280111931901419ab9c029028026135573ca00226ea8004d5d0a80299a80abae35742a008666aa03203640026ae85400cccd54065d710009aba15002301d357426ae8940088c98c8090cd5ce01281201109aba25001135744a00226ae8940044d5d1280089aba25001135744a00226ae8940044d5d1280089aba25001135744a00226aae7940044dd50009aba15002300d357426ae8940088c98c8058cd5ce00b80b00a080a89931900a99ab9c49010350543500015135573ca00226ea8004cd55404c888c94cd54cd4ccd54c05848004c8c848cc00488ccd401488008008004008d40048800448cc004894cd40084078400406c8c94cd4ccd5cd19b8f3500622002350012200201d01c1333573466e1cd401888004d4004880040740704070d400488008d5400488888888888802c406c4cd5ce2481115554784f206e6f7420636f6e73756d65640001a1533553353233019501e001355001222222222222008101a22135002222533500415335333573466e3c0092210002001f1333573466e1c005200202001f101f221021101b13357389211377726f6e6720616d6f756e74206d696e7465640001a101a135001220020081232230023758002640026aa034446666aae7c004940708cd406cc010d5d080118019aba2002012232323333573466e1cd55cea8012400046644246600200600460146ae854008c014d5d09aba2500223263201233573802602402026aae7940044dd50009191919191999ab9a3370e6aae75401120002333322221233330010050040030023232323333573466e1cd55cea8012400046644246600200600460266ae854008cd4034048d5d09aba2500223263201733573803002e02a26aae7940044dd50009aba150043335500875ca00e6ae85400cc8c8c8cccd5cd19b875001480108c84888c008010d5d09aab9e500323333573466e1d4009200223212223001004375c6ae84d55cf280211999ab9a3370ea00690001091100191931900c99ab9c01a019017016015135573aa00226ea8004d5d0a80119a804bae357426ae8940088c98c804ccd5ce00a00980889aba25001135744a00226aae7940044dd5000899aa800bae75a224464460046eac004c8004d5405c88c8cccd55cf8011280d119a80c9991091980080180118031aab9d5002300535573ca00460086ae8800c0404d5d080089119191999ab9a3370ea0029000119091180100198029aba135573ca00646666ae68cdc3a801240044244002464c6402066ae700440400380344d55cea80089baa001232323333573466e1d400520062321222230040053007357426aae79400c8cccd5cd19b875002480108c848888c008014c024d5d09aab9e500423333573466e1d400d20022321222230010053007357426aae7940148cccd5cd19b875004480008c848888c00c014dd71aba135573ca00c464c6402066ae7004404003803403002c4d55cea80089baa001232323333573466e1cd55cea80124000466442466002006004600a6ae854008dd69aba135744a004464c6401866ae700340300284d55cf280089baa0012323333573466e1cd55cea800a400046eb8d5d09aab9e500223263200a33573801601401026ea80048c8c8c8c8c8cccd5cd19b8750014803084888888800c8cccd5cd19b875002480288488888880108cccd5cd19b875003480208cc8848888888cc004024020dd71aba15005375a6ae84d5d1280291999ab9a3370ea00890031199109111111198010048041bae35742a00e6eb8d5d09aba2500723333573466e1d40152004233221222222233006009008300c35742a0126eb8d5d09aba2500923333573466e1d40192002232122222223007008300d357426aae79402c8cccd5cd19b875007480008c848888888c014020c038d5d09aab9e500c23263201333573802802602202001e01c01a01801626aae7540104d55cf280189aab9e5002135573ca00226ea80048c8c8c8c8cccd5cd19b875001480088ccc888488ccc00401401000cdd69aba15004375a6ae85400cdd69aba135744a00646666ae68cdc3a80124000464244600400660106ae84d55cf280311931900619ab9c00d00c00a009135573aa00626ae8940044d55cf280089baa001232323333573466e1d400520022321223001003375c6ae84d55cf280191999ab9a3370ea004900011909118010019bae357426aae7940108c98c8024cd5ce00500480380309aab9d50011375400224464646666ae68cdc3a800a40084244400246666ae68cdc3a8012400446424446006008600c6ae84d55cf280211999ab9a3370ea00690001091100111931900519ab9c00b00a008007006135573aa00226ea80048c8cccd5cd19b8750014800880308cccd5cd19b8750024800080308c98c8018cd5ce00380300200189aab9d37540029309000a48103505431003200135500822112225335001135003220012213335005220023004002333553007120010050040011112223003300200132001355006222533500110022213500222330073330080020060010033200135500522225335001100222135002225335333573466e1c005200000a0091333008007006003133300800733500b12333001008003002006003122002122001112200212212233001004003112323001001223300330020020011"}"""
