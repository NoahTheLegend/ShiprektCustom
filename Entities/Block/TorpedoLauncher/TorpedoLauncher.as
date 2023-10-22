#include "WeaponCommon.as";
#include "AccurateSoundPlay.as";
#include "ParticleSpark.as";

const f32 BULLET_SPEED = 2.0f;
const int FIRE_RATE_MANUAL = 30;

const u8 MAX_AMMO = 1;
const u8 REFILL_AMOUNT = 1;
const u8 REFILL_SECONDS = 30; // consider this also as the delay for reload after shooting
const u8 REFILL_SECONDARY_CORE_SECONDS = 40;
const u8 REFILL_SECONDARY_CORE_AMOUNT = 1;
const f32 TORPEDO_LIFETIME = 30;

Random _shotspreadrandom(0x11598); //clientside

void onInit(CBlob@ this)
{
	this.Tag("weapon");
	this.Tag("usesAmmo");
	
	this.Tag("noEnemyEntry");
	this.set_string("seat label", "Control Torpedo Launcher");
	this.set_u8("seat icon", 7);
	this.set_f32("weight", 6.5f);
	
	this.addCommandID("fire");

	if (isServer())
	{
		this.set_u16("ammo", MAX_AMMO);
		this.set_u16("maxAmmo", MAX_AMMO);
		this.Sync("ammo", true);
		this.Sync("maxAmmo", true);
	}

	CSprite@ sprite = this.getSprite();
    sprite.SetRelativeZ(2);

	this.set_u32("fire time", 0);
}

void onTick(CBlob@ this)
{
	const int col = this.getShape().getVars().customData;
	if (col <= 0) return; //not placed yet

	u16 operatorid = 0;
	AttachmentPoint@ seat = this.getAttachmentPoint(0);
	CBlob@ occupier = seat.getOccupied();
	if (occupier !is null)
	{
		this.set_u16("parentID", 0);
		Manual(this, occupier);

		operatorid = occupier.getNetworkID();
		this.set_u16("operatorid", operatorid);
	}

	if (isServer())
	{
		Ship@ ship = getShipSet().getShip(col);
		if (ship !is null)
		{
			checkDocked(this, ship);
			if (canShootManual(this))
				refillAmmo(this, ship, REFILL_AMOUNT, REFILL_SECONDS, REFILL_SECONDARY_CORE_AMOUNT, REFILL_SECONDARY_CORE_SECONDS);
		}
	}
}

void Manual(CBlob@ this, CBlob@ controller)
{
	Vec2f aimpos = controller.getAimPos();
	Vec2f pos = this.getPosition();
	Vec2f aimVec = aimpos - pos;

	// fire
	if (controller.isMyPlayer() && controller.isKeyJustPressed(key_action1) && canShootManual(this) && isClearShot(this, aimVec))
	{
		Fire(this, aimVec, controller.getNetworkID(), true);
	}
}

void Fire(CBlob@ this, Vec2f&in aimVector, const u16&in netid, const bool&in manual = false)
{
	CBitStream params;
	params.write_netid(netid);
	this.SendCommand(this.getCommandID("fire"), params);
	this.set_u32("fire time", getGameTime());
}

const bool isClearShot(CBlob@ this, Vec2f&in aimVec, const bool&in targetMerged = false)
{
	Vec2f pos = this.getPosition();
	const f32 distanceToTarget = Maths::Max(aimVec.Length(), 80.0f);
	CMap@ map = getMap();

	Vec2f offset = aimVec;
	offset.Normalize();
	offset *= 7.0f;

	HitInfo@[] hitInfos;
	map.getHitInfosFromRay(pos + offset.RotateBy(30), -aimVec.Angle(), distanceToTarget, this, @hitInfos);
	map.getHitInfosFromRay(pos + offset.RotateBy(-60), -aimVec.Angle(), distanceToTarget, this, @hitInfos);
	
	const u8 hitLength = hitInfos.length;
	if (hitLength > 0)
	{
		//HitInfo objects are sorted, first come closest hits
		for (u8 i = 0; i < hitLength; i++)
		{
			HitInfo@ hi = hitInfos[i];
			CBlob@ b = hi.blob;
			if (b is null || b is this) continue;

			const int thisColor = this.getShape().getVars().customData;
			const int bColor = b.getShape().getVars().customData;
			
			const bool sameShip = bColor != 0 && thisColor == bColor;
			const bool canShootSelf = targetMerged && hi.distance > distanceToTarget * 0.7f;

			if (b.hasTag("block") && b.getShape().getVars().customData > 0 && ((b.hasTag("solid") && !b.hasTag("plank")) || b.hasTag("weapon")) && sameShip && !canShootSelf)
			{
				return false;
			}
		}
	}
	
	//check to make sure we aren't shooting through rock
	Vec2f solidPos;
	if (map.rayCastSolid(pos, pos + aimVec, solidPos))
	{
		AttachmentPoint@ seat = this.getAttachmentPoint(0);
		CBlob@ occupier = seat.getOccupied();

		if (occupier is null) return false;
	}

	return true;
}

bool canShootManual(CBlob@ this)
{
	return this.get_u32("fire time") + FIRE_RATE_MANUAL < getGameTime();
}

const bool isClear(CBlob@ this)
{
	Vec2f aimVector = Vec2f(1, 0).RotateBy(this.getAngleDegrees());
	
	HitInfo@[] hitInfos;
	if (getMap().getHitInfosFromRay(this.getPosition(), -aimVector.Angle(), 60.0f, this, @hitInfos))
	{
		const u8 hitLength = hitInfos.length;
		for (u8 i = 0; i < hitLength; i++)
		{
			CBlob@ b =  hitInfos[i].blob;
			if (b is null || b is this) continue;

			if (this.getShape().getVars().customData == b.getShape().getVars().customData && 
			   (b.hasTag("weapon") || b.hasTag("door") ||(b.hasTag("solid") && !b.hasTag("plank")))) //same ship
			{
				return false;
			}
		}
	}

	return true;
}

void onCommand(CBlob@ this, u8 cmd, CBitStream@ params)
{
    if (cmd == this.getCommandID("fire"))
	{
		u16 shooterID;
		if (!params.saferead_netid(shooterID)) return;

		CBlob@ shooter = getBlobByNetworkID(shooterID);
		if (shooter is null) return;

		Ship@ ship = getShipSet().getShip(this.getShape().getVars().customData);
		if (ship is null) return;

		Vec2f pos = this.getPosition();

		if (!isClear(this))
		{
			directionalSoundPlay("lightup", pos);
			return;
		}

		//ammo
		u16 ammo = this.get_u16("ammo");

		if (ammo <= 0)
		{
			directionalSoundPlay("LoadingTick1", pos, 0.35f);
			return;
		}
		
		ammo--;
		this.set_u16("ammo", ammo);

		Vec2f aimvector = Vec2f(1, 0).RotateBy(this.getAngleDegrees());
		const Vec2f barrelPos = this.getPosition() + aimvector*9;
		Vec2f velocity = aimvector*BULLET_SPEED;

		shotParticles(barrelPos, aimvector.Angle(), false);
		directionalSoundPlay("LauncherFire" + (XORRandom(2) + 1), barrelPos, 1.0f, 0.85f);

		if (!canShootManual(this)) return;

		if (isServer())
		{
            CBlob@ bullet = server_CreateBlobNoInit("torpedo");
            if (bullet !is null)
            {
				bullet.server_setTeamNum(this.getTeamNum());
				bullet.setPosition(pos + aimvector*8.0f);

				if (shooter !is null)
				{
                	bullet.SetDamageOwnerPlayer(shooter.getPlayer());
					bullet.set_u16("shooter_id", shooter.getNetworkID());
					//bullet.server_SetPlayer(shooter.getPlayer());
                }

				bullet.Init();

                bullet.setVelocity(velocity + ship.vel);
				bullet.setAngleDegrees(-aimvector.Angle() + 90.0f);
                //bullet.server_SetTimeToDie(TORPEDO_LIFETIME); // set in projectile
            }
    	}

		this.set_u32("fire time", getGameTime());
    }
}
