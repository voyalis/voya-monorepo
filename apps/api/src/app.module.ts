// voya-monorepo/apps/api/src/app.module.ts
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { Message } from './messages/message.entity'; // Message entity'miz (bir önceki adımda oluşturmuştuk)
import { MessagesModule } from './messages/messages.module'; // Messages modülümüz

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: '.env', // Lokal geliştirme için .env dosyasını okur
      // Fly.io'da NODE_ENV=production olduğunda bu dosya okunmayacak,
      // bunun yerine Fly.io'ya set ettiğimiz ortam değişkenleri (secret'lar) kullanılacak.
      ignoreEnvFile: process.env.NODE_ENV === 'production',
    }),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const nodeEnv = configService.get<string>('NODE_ENV');
        const dbUrl = configService.get<string>('DATABASE_URL');

        console.log(`[AppModule] NODE_ENV: ${nodeEnv}`); // Kontrol için log
        if (dbUrl) {
          // DATABASE_URL varsa (Fly.io ortamında veya lokalde .env'de tanımlıysa)
          console.log(
            `[AppModule] Connecting to database using DATABASE_URL...`,
          );
          return {
            type: 'postgres',
            url: dbUrl, // Neon veya diğer PostgreSQL bağlantı dizesini doğrudan kullan
            entities: [Message], // Hangi tablolarla çalışacağımızı belirtiyoruz
            // synchronize: true, // GELİŞTİRME/TEST İÇİN true, ÜRETİMDE KESİNLİKLE FALSE! Migration kullanacağız.
            // ŞİMDİLİK TEST İÇİN true BIRAKALIM, Neon'da tabloyu oluşturması için.
            // SONRA BUNU FALSE YAPIP MIGRATION'LARA GEÇECEĞİZ.
            synchronize: nodeEnv !== 'production', // Production değilse true, production ise false
            logging: true, // SQL sorgularını konsolda gösterir
            ssl: dbUrl.includes('sslmode=require') // Neon genellikle SSL gerektirir
              ? { rejectUnauthorized: false } // Basit SSL ayarı, daha güvenlisi için sertifika gerekebilir
              : false,
          };
        } else if (nodeEnv !== 'production') {
          // DATABASE_URL yok AMA production ORTAMINDA DEĞİLSEK (lokal geliştirme gibi)
          // .env dosyasındaki bireysel parametreleri kullan
          console.warn(
            '[AppModule] DATABASE_URL not found, using individual DB parameters from .env for local development...',
          );
          return {
            type: 'postgres',
            host: configService.get<string>('DATABASE_HOST'),
            port: parseInt(
              configService.get<string>('DATABASE_PORT') || '5433',
            ),
            username: configService.get<string>('DATABASE_USER'),
            password: configService.get<string>('DATABASE_PASSWORD'),
            database: configService.get<string>('DATABASE_DB_NAME'),
            entities: [Message],
            synchronize: true, // Lokal geliştirme için true
            logging: true,
            ssl: false,
          };
        } else {
          // DATABASE_URL yok VE production ORTAMINDAYSAK, bu bir hata!
          // Uygulamanın başlamasını engellemek için hata fırlat.
          console.error(
            '❌ [AppModule] FATAL ERROR: DATABASE_URL environment variable is missing in production!',
          );
          throw new Error(
            'FATAL ERROR: DATABASE_URL environment variable is missing in production!',
          );
        }
      },
    }),
    MessagesModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
