// voya-monorepo/apps/api/src/messages/messages.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message } from './message.entity';

// DTO (Data Transfer Object) - Gelen verinin şeklini tanımlar
export class CreateMessageDto {
  text: string;
}

@Injectable()
export class MessagesService {
  constructor(
    @InjectRepository(Message) // Message Repository'sini enjekte et
    private messagesRepository: Repository<Message>,
  ) {}

  async create(createMessageDto: CreateMessageDto): Promise<Message> {
    const newMessage = this.messagesRepository.create(createMessageDto); // Yeni mesaj nesnesi oluştur
    return this.messagesRepository.save(newMessage); // Veritabanına kaydet
  }

  async findAll(): Promise<Message[]> {
    return this.messagesRepository.find(); // Tüm mesajları bul ve döndür
  }
}
