from sqlalchemy import Column, Integer, String, TIMESTAMP, func
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class UserStatus(Base):
    __tablename__ = "user_status"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String(50), nullable=False)
    status = Column(String(20), nullable=False)
    team = Column(String(50), nullable=True)
    updated_at = Column(TIMESTAMP, server_default=func.now(), onupdate=func.now())
