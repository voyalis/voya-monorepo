// voya-monorepo/apps/api/src/messages/messages.module.ts
import { Module } from '@nestjs/common';
import { MessagesService } from './messages.service';
import { MessagesController } from './messages.controller';
import { TypeOrmModule } from '@nestjs/typeorm'; // Bunu import edin
import { Message } from './message.entity'; // Oluşturduğumuz entity'yi import edin

@Module({
  imports: [TypeOrmModule.forFeature([Message])], // Bu satırı ekleyin
  controllers: [MessagesController],
  providers: [MessagesService],
})
export class MessagesModule {}
