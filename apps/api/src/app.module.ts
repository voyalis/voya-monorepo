// voya-monorepo/apps/api/src/app.module.ts
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule } from '@nestjs/typeorm';
// ConfigModule ve ConfigService importlarını ŞİMDİLİK YORUMLAYIN veya SİLİN
// import { ConfigModule, ConfigService } from '@nestjs/config';
import { Message } from './messages/message.entity'; // Message entity'sini direkt import ediyoruz

// MessagesModule importunu da ŞİMDİLİK YORUMLAYIN veya SİLİN
// import { MessagesModule } from './messages/messages.module';

@Module({
  imports: [
    // ConfigModule.forRoot(...), // BU KISMI ŞİMDİLİK YORUMLAYIN veya SİLİN
    TypeOrmModule.forRoot({
      // forRootAsync yerine direkt forRoot kullanıyoruz
      type: 'postgres',
      host: 'localhost', // Bilgileri doğrudan yazıyoruz
      port: 5433,
      username: 'voyas_user',
      password: 'StrongPassword123!',
      database: 'voyas_dev_db',
      entities: [Message], // Glob deseni yerine direkt entity sınıfını verdik
      synchronize: true,
      logging: true,
    }),
    // MessagesModule, // BU SATIRI DA ŞİMDİLİK YORUMLAYIN veya SİLİN
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
