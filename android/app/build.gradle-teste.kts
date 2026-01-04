android {
    compileSdkVersion 34
    
    defaultConfig {
        applicationId "com.example.energycontrol"
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 1
        versionName "2.0.0"
        
        // Adicionar para SQLite
        multiDexEnabled true
    }
    
    buildTypes {
        release {
            signingConfig signingConfigs.debug
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }
}