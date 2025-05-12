// voya-monorepo/apps/api/src/app.module.ts
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { Message } from './messages/message.entity';
import { MessagesModule } from './messages/messages.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // .env dosyasını hala lokal geliştirme için kullanabiliriz,
      // ama Fly.io'da ortam değişkenleri öncelikli olacaktır.
      envFilePath: '.env',
      ignoreEnvFile: process.env.NODE_ENV === 'production', // Üretimde .env dosyasını yok sayabiliriz
    }),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const dbUrl = configService.get<string>('DATABASE_URL'); // Fly.io secret'ından gelecek
        if (!dbUrl) {
          // Lokal geliştirme için .env'den eski parametreleri kullan (opsiyonel fallback)
          // Veya burada bir hata fırlatabilirsiniz eğer DATABASE_URL yoksa.
          // Şimdilik, eğer DATABASE_URL yoksa lokal .env'ye güvensin diyeceğiz,
          // ama Fly.io'da DATABASE_URL kesinlikle set edilmiş olmalı.
          console.warn(
            'DATABASE_URL not found, attempting to use individual DB params from .env for local dev',
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
            synchronize: true, // GELİŞTİRME İÇİN true, ÜRETİMDE KESİNLİKLE FALSE!
            logging: true,
            ssl: false, // Lokal için ssl false olabilir
          };
        }

        // Neon (veya çoğu bulut veritabanı) SSL gerektirir.
        // Bağlantı dizesinde ?sslmode=require varsa TypeORM bunu anlar.
        // Ekstra SSL ayarları gerekebilir:
        return {
          type: 'postgres',
          url: dbUrl, // Neon bağlantı dizesini doğrudan kullan
          entities: [Message],
          synchronize: true, // GELİŞTİRME/TEST İÇİN true, ÜRETİMDE KESİNLİKLE FALSE!
          logging: true,
          ssl: dbUrl.includes('sslmode=require')
            ? { rejectUnauthorized: false }
            : false, // Basit bir SSL ayarı, Neon için gerekebilir.
          // Daha güvenli SSL için sertifika ayarları gerekebilir.
        };
      },
    }),
    MessagesModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
