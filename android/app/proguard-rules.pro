# ML Kit text recognition : on n'utilise que le script latin.
# Les recognizers optionnels (chinois, devanagari, japonais, coréen) ne sont pas
# bundlés → R8 signale des classes manquantes. On les ignore explicitement.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
