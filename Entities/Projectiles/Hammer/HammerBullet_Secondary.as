#include "ExplosionEffects.as";;
#include "DamageBooty.as";
#include "AccurateSoundPlay.as";
#include "ParticleSpark.as";
#include "Hitters.as";
#include "PlankCommon.as";
#include "WaterEffects.as";

const f32 EXPLODE_RADIUS = 8.0f;
const f32 FLAK_REACH = 50.0f;

BootyRewards@ booty_reward;

void onInit(CBlob@ this)
{
	if (booty_reward is null)
	{
		BootyRewards _booty_reward;
		_booty_reward.addTagReward("bomb", 4);
		_booty_reward.addTagReward("engine", 2);
		_booty_reward.addTagReward("mothership", 8);
		_booty_reward.addTagReward("secondarycore", 6);
		_booty_reward.addTagReward("weapon", 5);
		@booty_reward = _booty_reward;
	}
	
	this.Tag("flak shell");
	this.Tag("projectile");

	ShapeConsts@ consts = this.getShape().getConsts();
	consts.mapCollisions = true;
	consts.bullet = true;

	this.getSprite().SetZ(550.0f);
	
	//shake screen (onInit accounts for firing latency)
	CPlayer@ localPlayer = getLocalPlayer();
	if (localPlayer !is null && localPlayer is this.getDamageOwnerPlayer())
		ShakeScreen(4, 4, this.getPosition());
}

void onDie(CBlob@ this)
{
	Vec2f pos = this.getPosition();

	if (this.hasTag("sunk"))
	{
		if (isClient())
		{
			MakeWaterParticle(pos, Vec2f_zero);
			directionalSoundPlay("WaterSplashBall.ogg", pos);
		}
		return;
	}
	
	if (isClient())
	{
		directionalSoundPlay("FlakExp"+XORRandom(2), pos, 2.5f);
		for (u8 i = 0; i < (v_fastrender ? 1 : 3); i++)
		{
			blast(pos, v_fastrender ? 1 : 3);	
		}
	}

	if (isServer())
	{
		//splash damage
		CBlob@[] blobsInRadius;
		if (getMap().getBlobsInRadius(pos, EXPLODE_RADIUS, @blobsInRadius))
		{
			const u8 blobsLength = blobsInRadius.length;
			for (u8 i = 0; i < blobsLength; i++)
			{
				CBlob@ b = blobsInRadius[i];
				if (b.hasTag("block") && b.getShape().getVars().customData > 0)
					this.server_Hit(b, Vec2f_zero, Vec2f_zero, getDamage(b), Hitters::explosion, false);
			}
		}
	}
}

f32 getDamage(CBlob@ hitBlob)
{
	if (hitBlob.hasTag("bomb"))
		return 4.0f;
	if (hitBlob.hasTag("ram"))
		return 2.0f;
	if (hitBlob.hasTag("propeller"))
		return 0.75f;
	if (hitBlob.hasTag("antiram"))
		return 1.0f;
	if (hitBlob.hasTag("ramengine"))
		return 1.0f;
	if (hitBlob.hasTag("door"))
		return 0.5f;
	if (hitBlob.getName() == "shark" || hitBlob.getName() == "human")
		return 1.0f;
	if (hitBlob.hasTag("seat") || hitBlob.hasTag("weapon"))
		return 0.25f;
	if (hitBlob.hasTag("mothership") || hitBlob.hasTag("secondaryCore"))
		return 0.4f;
	if (hitBlob.hasTag("decoycore"))
		return 0.3f;
	
	return 0.5f;
}

void onHitBlob(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitBlob, u8 customData)
{
	if (hitBlob.hasTag("block"))
	{
		Vec2f vel = worldPoint - hitBlob.getPosition();//todo: calculate real bounce angles?
		ShrapnelParticle( worldPoint, vel );
		directionalSoundPlay( "Ricochet" +  ( XORRandom(3) + 1 ) + ".ogg", worldPoint, 0.35f );
	}
}

void onCollision(CBlob@ this, CBlob@ b, bool solid, Vec2f normal, Vec2f point1)
{
	if (this.hasTag("killed")) return;
	Vec2f pos = this.getPosition();

	if (b.hasTag("plank") && !CollidesWithPlank(b, this.getVelocity()))
		return;

	bool killed = false;
	const int color = b.getShape().getVars().customData;
	const bool sameTeam = b.getTeamNum() == this.getTeamNum();
	const bool isBlock = b.hasTag("block");
	
	if (color > 0 || !isBlock)
	{
		if (isBlock)
		{
			if (b.hasTag("solid") || (b.hasTag("door") && b.getShape().getConsts().collidable) || 
				(!sameTeam && (b.hasTag("core") || b.hasTag("weapon") || b.hasTag("bomb")))) //hit these and die
			{
				killed = true;
			}
			else if (b.hasTag("hasSeat"))
			{
				AttachmentPoint@ seat = b.getAttachmentPoint(0);
				CBlob@ occupier = seat.getOccupied();
				if (occupier !is null && occupier.getName() == "human" && occupier.getTeamNum() != this.getTeamNum())
				{
					killed = true;
				}
				else return;
			}
			else return;
		}
		else
		{
			if (sameTeam || (b.hasTag("player") && b.isAttached()) || b.hasTag("projectile")) //don't hit
				return;
		}
		
		if (!isServer()) return;

		const int thisColor = this.get_u32("color");
		
		if (killed) 
		{
			this.Tag("killed");
			CBlob@[] blobs;
			if (getMap().getBlobsInRadius(pos, Maths::Min(float(5 + this.getTickSinceCreated()), EXPLODE_RADIUS), @blobs))
			{
				for (uint i = 0; i < blobs.length; i++)
				{
					CBlob@ b = blobs[i];
					if (b is null) continue;

					const int color = b.getShape().getVars().customData;
					if (b.hasTag("block") && color > 0 && color != thisColor && b.hasTag("solid"))
						this.server_Die();
				}
			}

			this.server_Die(); 
			return;
		}
	}
}

Random _blast_r(0x10002);
void blast(const Vec2f pos, const u8 amount)
{
	for (u8 i = 0; i < amount; i++)
    {
        Vec2f vel(_blast_r.NextFloat() * 2.5f, 0);
        vel.RotateBy(_blast_r.NextFloat() * 360.0f);

        CParticle@ p = ParticleAnimated(CFileMatcher("GenericBlast6.png").getFirst(), 
									pos, 
									vel, 
									float(XORRandom(360)), 
									1.0f, 
									2 + XORRandom(4), 
									0.0f, 
									false);
									
        if (p is null) return; //bail if we stop getting particles
		
        p.scale = 0.5f + _blast_r.NextFloat()*0.5f;
        p.damping = 0.85f;
		p.Z = 650.0f;
    }
}
