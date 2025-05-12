import { Test, TestingModule } from '@nestjs/testing';
import { MessagesService, CreateMessageDto } from './messages.service'; // CreateMessageDto'yu da import ettik
import { getRepositoryToken } from '@nestjs/typeorm';
import { Message } from './message.entity';
import { Repository } from 'typeorm';

const mockMessageRepository = {
  create: jest.fn(),
  save: jest.fn(),
  find: jest.fn(),
};

describe('MessagesService', () => {
  let service: MessagesService;
  let repository: Repository<Message>; // Bu değişken için uyarı alıyordunuz

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MessagesService,
        {
          provide: getRepositoryToken(Message),
          useValue: mockMessageRepository,
        },
      ],
    }).compile();

    service = module.get<MessagesService>(MessagesService);
    repository = module.get<Repository<Message>>(getRepositoryToken(Message));
  });

  it('should be defined', () => {
    expect(service).toBeDefined(); // 'service' burada kullanılıyor
    expect(repository).toBeDefined(); // 'repository' için uyarıyı gidermek amacıyla eklendi
    // Hatta daha spesifik olarak mock'ladığımız bir metodu kontrol edebiliriz:
    // expect(repository.create).toBeDefined();
  });

  describe('create', () => {
    it('should create and save a new message', async () => {
      const createMessageDto: CreateMessageDto = { text: 'Test message' }; // CreateMessageDto tipini belirttik
      const messageToCreate = { text: 'Test message' }; // save'e gönderilen obje
      const expectedSavedMessage: Message = {
        // Dönen sonucun Message tipinde olmasını bekliyoruz
        id: 'some-uuid',
        text: 'Test message',
        createdAt: new Date(),
      };

      // service.create metodu içinde repository.create çağrılacak, sonra repository.save
      // mockMessageRepository.create, DTO'yu alır ve bir entity nesnesi döndürür (veya DTO'nun kendisini)
      mockMessageRepository.create.mockReturnValue(messageToCreate);
      // mockMessageRepository.save, bu entity nesnesini alır ve kaydedilmiş entity'yi (ID ve createdAt ile) döndürür
      mockMessageRepository.save.mockResolvedValue(expectedSavedMessage);

      const result = await service.create(createMessageDto);

      expect(mockMessageRepository.create).toHaveBeenCalledWith(
        createMessageDto,
      );
      expect(mockMessageRepository.save).toHaveBeenCalledWith(messageToCreate); // create'den dönen nesne ile çağrılmalı
      expect(result).toEqual(expectedSavedMessage);
    });
  });

  describe('findAll', () => {
    it('should return an array of messages', async () => {
      const expectedMessages: Message[] = [
        // Dönen sonucun Message[] tipinde olmasını bekliyoruz
        { id: 'uuid1', text: 'Msg1', createdAt: new Date() },
      ];
      mockMessageRepository.find.mockResolvedValue(expectedMessages);

      const result = await service.findAll();
      expect(mockMessageRepository.find).toHaveBeenCalled();
      expect(result).toEqual(expectedMessages);
    });
  });
});
